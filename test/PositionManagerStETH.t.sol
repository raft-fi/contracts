// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IERC20Indexable } from "../contracts/Interfaces/IERC20Indexable.sol";
import { IWstETHWrapper } from "../contracts/Interfaces/IWstETHWrapper.sol";
import { IStETH } from "../contracts/Dependencies/IStETH.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { PositionManager } from "../contracts/PositionManager.sol";
import { IERC20Wrapped, PositionManagerStETH } from "../contracts/PositionManagerStETH.sol";
import { SplitLiquidationCollateral } from "../contracts/SplitLiquidationCollateral.sol";
import { WrappedCollateralToken } from "../contracts/WrappedCollateralToken.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";
import { PriceFeedTestnet } from "./mocks/PriceFeedTestnet.sol";

contract PositionManagerStETHTest is TestSetup {
    address public constant WSTETH_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    PriceFeedTestnet public priceFeed;
    PositionManagerStETH public positionManagerStETH;
    WrappedCollateralToken public wrappedCollateralToken;
    IStETH public stETH;

    function setUp() public override {
        vm.createSelectFork("mainnet", 16_974_953);

        super.setUp();

        wrappedCollateralToken = new WrappedCollateralToken(
            IERC20(WSTETH_ADDRESS), 
            "Wrapped Collateral Token",
            "WCT", 
            100_000_0e18, 
            type(uint256).max, 
            address(positionManager)
        );

        priceFeed = new PriceFeedTestnet();
        positionManager.addCollateralToken(wrappedCollateralToken, priceFeed, splitLiquidationCollateral);

        positionManagerStETH = new PositionManagerStETH(
            address(positionManager),
            IERC20Wrapped(address(wrappedCollateralToken))
        );
        stETH = positionManagerStETH.stETH();

        wrappedCollateralToken.whitelistAddress(address(positionManagerStETH), true);

        vm.prank(ALICE);
        positionManager.whitelistDelegate(address(positionManagerStETH), true);
    }

    function testGetPositionStETH() public {
        _depositETH(ALICE, 50 ether);

        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory alicePosition = PositionManagerUtils.openPositionStETH({
            positionManagerStETH: positionManagerStETH,
            priceFeed: priceFeed,
            icr: 150 * MathUtils._100_PERCENT / 100,
            extraDebt: 0
        });
        vm.stopPrank();

        (IERC20Indexable raftCollateralToken, IERC20Indexable raftDebtToken,,,,,,,,) =
            positionManager.collateralInfo(wrappedCollateralToken);
        uint256 alicePositionCollateral = raftCollateralToken.balanceOf(ALICE);
        uint256 aliceDebt = raftDebtToken.balanceOf(ALICE);

        assertEq(alicePositionCollateral, alicePosition.collateral);
        assertEq(aliceDebt, alicePosition.totalDebt);
    }

    function testDepositStETH() public {
        _depositETH(ALICE, 50 ether);

        uint256 rBalanceBefore = positionManager.rToken().balanceOf(ALICE);
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory result = PositionManagerUtils.openPositionStETH({
            positionManagerStETH: positionManagerStETH,
            priceFeed: priceFeed,
            icr: 2 * MathUtils._100_PERCENT,
            extraDebt: 0
        });
        vm.stopPrank();
        assertGt(positionManager.rToken().balanceOf(ALICE), rBalanceBefore);

        (IERC20Indexable raftCollateralToken,,,,,,,,,) = positionManager.collateralInfo(wrappedCollateralToken);

        uint256 positionCollateralBefore = raftCollateralToken.balanceOf(ALICE);
        assertEq(positionCollateralBefore, result.collateral);

        uint256 positionManagerStETHBalanceBefore = wrappedCollateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerStETHBalanceBefore, result.collateral);

        uint256 collateralTopUpAmount = 1 ether;

        vm.startPrank(ALICE);
        uint256 wstETHAmount = stETH.getSharesByPooledEth(collateralTopUpAmount);
        stETH.approve(address(positionManagerStETH), collateralTopUpAmount);
        positionManagerStETH.managePositionStETH(collateralTopUpAmount, true, 0, false, 0, emptySignature);
        vm.stopPrank();

        uint256 positionCollateralAfter = raftCollateralToken.balanceOf(ALICE);
        assertEq(positionCollateralAfter, positionCollateralBefore + wstETHAmount);

        uint256 positionManagerStETHBalanceAfter = wrappedCollateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerStETHBalanceAfter, positionManagerStETHBalanceBefore + wstETHAmount);
    }

    // Sends the correct amount of stETH to the user
    function testWithdrawStETH() public {
        _depositETH(ALICE, 50 ether);

        vm.startPrank(ALICE);
        PositionManagerUtils.openPositionStETH({
            positionManagerStETH: positionManagerStETH,
            priceFeed: priceFeed,
            icr: 2 * MathUtils._100_PERCENT,
            extraDebt: 0
        });
        vm.stopPrank();

        uint256 aliceBalanceBefore = stETH.balanceOf(ALICE);
        uint256 withdrawAmount = 1 ether;

        // Alice withdraws 1 stETH
        vm.prank(ALICE);
        positionManagerStETH.managePositionStETH(withdrawAmount, false, 0, false, 0, emptySignature);
        assertApproxEqAbs(stETH.balanceOf(ALICE), aliceBalanceBefore + withdrawAmount, 2);
    }

    // Sends the correct amount of stETH to the user
    function testWithdrawStETHAlongWithRRepayment() public {
        _depositETH(ALICE, 50 ether);

        vm.startPrank(ALICE);
        PositionManagerUtils.openPositionStETH({
            positionManagerStETH: positionManagerStETH,
            priceFeed: priceFeed,
            icr: 2 * MathUtils._100_PERCENT,
            extraDebt: 2 ether
        });
        vm.stopPrank();

        uint256 aliceBalanceBefore = stETH.balanceOf(ALICE);
        uint256 withdrawAmount = 1 ether;

        uint256 rBalanceBefore = positionManager.rToken().balanceOf(ALICE);

        // Alice withdraws 1 wstETH
        vm.startPrank(ALICE);
        positionManager.rToken().approve(address(positionManagerStETH), 1 ether);
        positionManagerStETH.managePositionStETH(withdrawAmount, false, 1 ether, false, 0, emptySignature);
        vm.stopPrank();

        assertEq(positionManager.rToken().balanceOf(ALICE), rBalanceBefore - 1 ether);
        assertApproxEqAbs(stETH.balanceOf(ALICE), aliceBalanceBefore + withdrawAmount, 2);
    }

    function _depositETH(address _account, uint256 _amount) private {
        vm.prank(_account);
        IStETH(address(stETH)).submit{ value: _amount }(_account);
    }
}
