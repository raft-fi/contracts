// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PriceFeedTestnet } from "./mocks/PriceFeedTestnet.sol";
import { IRToken } from "../contracts/Interfaces/IRToken.sol";
import { IPositionManager } from "../contracts/Interfaces/IPositionManager.sol";
import { IPSM } from "../contracts/PSM/IPSM.sol";
import { IChai } from "../contracts/PSM/IChai.sol";
import { ILock } from "../contracts/Interfaces/ILock.sol";
import { ChaiPSM } from "../contracts/PSM/ChaiPSM.sol";
import { ConstantPriceFeed } from "../contracts/PSM/ConstantPriceFeed.sol";
import { PSMFixedFee } from "../contracts/PSM/FixedFee.sol";
import { PSMSplitLiquidationCollateral } from "../contracts/PSM/PSMSplitLiquidationCollateral.sol";

contract ChaiPSMIntegrationTests is Test {
    IERC20 public constant DAI = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
    IRToken public constant R = IRToken(address(0x183015a9bA6fF60230fdEaDc3F43b3D788b13e21));
    IChai public constant CHAI = IChai(address(0x06AF07097C9Eeb7fD685c692751D5C66dB49c215));

    address public constant OWNER = address(0xaB40A7e3cEF4AfB323cE23B6565012Ac7c76BFef);
    address public constant DAI_WHALE = address(0x66F62574ab04989737228D18C3624f7FC1edAe14);

    ChaiPSM public psm;

    PriceFeedTestnet public daiPriceFeed;

    function setUp() public {
        vm.createSelectFork("mainnet", 18_004_964);
        daiPriceFeed = new PriceFeedTestnet();
        daiPriceFeed.setPrice(1e18);
        psm = new ChaiPSM(DAI, R, new PSMFixedFee(1e17, 1e17, daiPriceFeed, 95e16), CHAI);
        vm.startPrank(OWNER);
        psm.positionManager().addCollateralToken(
            psm, new ConstantPriceFeed(address(psm)), new PSMSplitLiquidationCollateral()
        );
        vm.stopPrank();
    }

    function testMintRAndBuyReserve() public {
        IPositionManager positionManager = psm.positionManager();
        uint256 daiBefore = DAI.balanceOf(DAI_WHALE);

        vm.expectRevert(IPSM.ZeroInputProvided.selector);
        psm.buyR(1000e18, 0);
        vm.expectRevert(IPSM.ZeroInputProvided.selector);
        psm.buyR(0, 900e18);

        vm.startPrank(DAI_WHALE);
        DAI.approve(address(psm), 1000e18);
        vm.expectRevert(abi.encodeWithSelector(IPSM.ReturnLessThanMinimum.selector, 900e18, 901e18));
        psm.buyR(1000e18, 901e18);

        psm.buyR(1000e18, 900e18);
        assertEq(R.balanceOf(DAI_WHALE), 900e18);
        assertEq(DAI.balanceOf(DAI_WHALE), daiBefore - 1000e18);
        assertEq(positionManager.raftDebtToken(psm).balanceOf(address(psm)), 900e18);
        assertEq(positionManager.raftCollateralToken(psm).balanceOf(address(psm)), 900e18);

        daiBefore = DAI.balanceOf(DAI_WHALE);
        R.approve(address(psm), 100e18);

        vm.expectRevert(IPSM.ZeroInputProvided.selector);
        psm.buyReserveToken(100e18, 0);
        vm.expectRevert(IPSM.ZeroInputProvided.selector);
        psm.buyReserveToken(0, 90e18);
        vm.expectRevert(abi.encodeWithSelector(IPSM.ReturnLessThanMinimum.selector, 90e18, 91e18));
        psm.buyReserveToken(100e18, 91e18);

        psm.buyReserveToken(100e18, 90e18);
        assertEq(R.balanceOf(DAI_WHALE), 800e18);
        assertEq(DAI.balanceOf(DAI_WHALE), daiBefore + 90e18);
        assertEq(positionManager.raftDebtToken(psm).balanceOf(address(psm)), 800e18);
        assertEq(positionManager.raftCollateralToken(psm).balanceOf(address(psm)), 800e18);
        vm.stopPrank();

        vm.expectRevert(ILock.ContractLocked.selector);
        positionManager.liquidate(address(psm));

        vm.expectRevert(ILock.ContractLocked.selector);
        positionManager.redeemCollateral(psm, 1, 1e18);
    }

    function testFurtherMintingInCaseOfDepeg() public {
        daiPriceFeed.setPrice(94e16);
        vm.startPrank(DAI_WHALE);
        DAI.approve(address(psm), 1000e18);
        vm.expectRevert(abi.encodeWithSelector(PSMFixedFee.DisabledBecauseOfReserveDepeg.selector, 94e16));
        psm.buyR(1000e18, 901e18);
    }
}
