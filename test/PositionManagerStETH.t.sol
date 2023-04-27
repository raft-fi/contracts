// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Indexable } from "../contracts/Interfaces/IERC20Indexable.sol";
import { IStETH } from "../contracts/Dependencies/IStETH.sol";
import { IWstETH } from "../contracts/Dependencies/IWstETH.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { PositionManager } from "../contracts/PositionManager.sol";
import { IPositionManagerStETH, PositionManagerStETH } from "../contracts/PositionManagerStETH.sol";
import { SplitLiquidationCollateral } from "../contracts/SplitLiquidationCollateral.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";
import { PriceFeedTestnet } from "./mocks/PriceFeedTestnet.sol";

contract PositionManagerStETHTest is TestSetup {
    address public constant WSTETH_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    PriceFeedTestnet public priceFeed;
    PositionManagerStETH public positionManagerStETH;
    PositionManager public positionManager;
    IStETH public stETH;
    SplitLiquidationCollateral public splitLiquidationCollateralNew;

    function setUp() public override {
        vm.createSelectFork("mainnet", 16_974_953);

        priceFeed = new PriceFeedTestnet();
        splitLiquidationCollateralNew = new SplitLiquidationCollateral();
        positionManager = new PositionManager(
            splitLiquidationCollateralNew
        );
        positionManager.addCollateralToken(IERC20(WSTETH_ADDRESS), priceFeed);

        positionManagerStETH = new PositionManagerStETH(
            address(positionManager),
            IWstETH(WSTETH_ADDRESS)
        );
        stETH = positionManagerStETH.stETH();

        vm.prank(ALICE);
        positionManager.whitelistDelegate(address(positionManagerStETH), true);
    }

    function testCannotCreatePositionManagerStETH() public {
        vm.expectRevert(IPositionManagerStETH.WstETHAddressCannotBeZero.selector);
        new PositionManagerStETH(
            address(positionManager),
            IWstETH(address(0))
        );
    }

    function testGetPositionETH() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory alicePosition = PositionManagerUtils.openPositionStETH({
            positionManagerStETH: positionManagerStETH,
            priceFeed: priceFeed,
            icr: 150 * MathUtils._100_PERCENT / 100,
            ethType: PositionManagerUtils.ETHType.ETH
        });
        vm.stopPrank();

        (IERC20Indexable raftCollateralToken,) = positionManager.raftCollateralTokens(IERC20(WSTETH_ADDRESS));
        uint256 alicePositionCollateral = raftCollateralToken.balanceOf(ALICE);
        uint256 aliceDebt = positionManager.raftDebtToken().balanceOf(ALICE);

        assertEq(alicePositionCollateral, alicePosition.collateral);
        assertEq(aliceDebt, alicePosition.totalDebt);
    }

    function testGetPositionStETH() public {
        _depositETH(ALICE, 50 ether);

        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory alicePosition = PositionManagerUtils.openPositionStETH({
            positionManagerStETH: positionManagerStETH,
            priceFeed: priceFeed,
            icr: 150 * MathUtils._100_PERCENT / 100,
            ethType: PositionManagerUtils.ETHType.STETH
        });
        vm.stopPrank();

        (IERC20Indexable raftCollateralToken,) = positionManager.raftCollateralTokens(IERC20(WSTETH_ADDRESS));
        uint256 alicePositionCollateral = raftCollateralToken.balanceOf(ALICE);
        uint256 aliceDebt = positionManager.raftDebtToken().balanceOf(ALICE);

        assertEq(alicePositionCollateral, alicePosition.collateral);
        assertEq(aliceDebt, alicePosition.totalDebt);
    }

    function testDepositETH() public {
        IERC20 _collateralToken = IERC20(WSTETH_ADDRESS);
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory result = PositionManagerUtils.openPositionStETH({
            positionManagerStETH: positionManagerStETH,
            priceFeed: priceFeed,
            icr: 2 ether,
            ethType: PositionManagerUtils.ETHType.ETH
        });
        vm.stopPrank();

        (IERC20Indexable raftCollateralToken,) = positionManager.raftCollateralTokens(_collateralToken);

        uint256 positionCollateralBefore = raftCollateralToken.balanceOf(ALICE);
        assertEq(positionCollateralBefore, result.collateral);

        uint256 positionManagerStETHBalanceBefore = _collateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerStETHBalanceBefore, result.collateral);

        uint256 collateralTopUpAmount = 1 ether;

        vm.startPrank(ALICE);
        uint256 wstETHAmount = stETH.getSharesByPooledEth(collateralTopUpAmount);
        positionManagerStETH.managePositionETH{ value: collateralTopUpAmount }(0, false, 0);
        vm.stopPrank();

        uint256 positionCollateralAfter = raftCollateralToken.balanceOf(ALICE);
        assertEq(positionCollateralAfter, positionCollateralBefore + wstETHAmount);

        uint256 positionManagerStETHBalanceAfter = _collateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerStETHBalanceAfter, positionManagerStETHBalanceBefore + wstETHAmount);
    }

    function testCannotDepositETH() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPositionStETH({
            positionManagerStETH: positionManagerStETH,
            priceFeed: priceFeed,
            icr: 2 ether,
            ethType: PositionManagerUtils.ETHType.ETH
        });
        vm.stopPrank();

        vm.startPrank(ALICE);
        vm.expectRevert(IPositionManagerStETH.SendingEtherFailed.selector);
        positionManagerStETH.managePositionETH{ value: 0 }(0, false, 0);
        vm.stopPrank();
    }

    function testDepositStETH() public {
        _depositETH(ALICE, 50 ether);

        IERC20 _collateralToken = IERC20(WSTETH_ADDRESS);

        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory result = PositionManagerUtils.openPositionStETH({
            positionManagerStETH: positionManagerStETH,
            priceFeed: priceFeed,
            icr: 2 ether,
            ethType: PositionManagerUtils.ETHType.STETH
        });
        vm.stopPrank();

        (IERC20Indexable raftCollateralToken,) = positionManager.raftCollateralTokens(_collateralToken);

        uint256 positionCollateralBefore = raftCollateralToken.balanceOf(ALICE);
        assertEq(positionCollateralBefore, result.collateral);

        uint256 positionManagerStETHBalanceBefore = _collateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerStETHBalanceBefore, result.collateral);

        uint256 collateralTopUpAmount = 1 ether;

        vm.startPrank(ALICE);
        uint256 wstETHAmount = stETH.getSharesByPooledEth(collateralTopUpAmount);
        stETH.approve(address(positionManagerStETH), collateralTopUpAmount);
        positionManagerStETH.managePositionStETH(collateralTopUpAmount, true, 0, false, 0);
        vm.stopPrank();

        uint256 positionCollateralAfter = raftCollateralToken.balanceOf(ALICE);
        assertEq(positionCollateralAfter, positionCollateralBefore + wstETHAmount);

        uint256 positionManagerStETHBalanceAfter = _collateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerStETHBalanceAfter, positionManagerStETHBalanceBefore + wstETHAmount);
    }

    // Sends the correct amount of stETH to the user
    function testWithdrawStETH() public {
        _depositETH(ALICE, 50 ether);

        vm.startPrank(ALICE);
        PositionManagerUtils.openPositionStETH({
            positionManagerStETH: positionManagerStETH,
            priceFeed: priceFeed,
            icr: 2 ether,
            ethType: PositionManagerUtils.ETHType.STETH
        });
        vm.stopPrank();

        uint256 aliceBalanceBefore = stETH.balanceOf(ALICE);
        uint256 withdrawAmount = 1 ether;
        uint256 stETHAmount = stETH.getPooledEthByShares(withdrawAmount);

        // Alice withdraws 1 wstETH
        vm.prank(ALICE);
        positionManagerStETH.managePositionStETH(withdrawAmount, false, 0, false, 0);

        uint256 aliceBalanceAfter = stETH.balanceOf(ALICE);
        assertApproxEqAbs(aliceBalanceAfter, aliceBalanceBefore + stETHAmount, 1);
    }

    function _depositETH(address _account, uint256 _amount) private {
        vm.startPrank(_account);
        IStETH(address(stETH)).submit{ value: _amount }(ALICE);
        vm.stopPrank();
    }
}
