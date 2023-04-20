// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IPositionManager} from "../contracts/Interfaces/IPositionManager.sol";
import {PositionManager} from "../contracts/PositionManager.sol";
import {MathUtils} from "../contracts/Dependencies/MathUtils.sol";
import {PriceFeedTestnet} from "./TestContracts/PriceFeedTestnet.sol";
import {PositionManagerUtils} from "./utils/PositionManagerUtils.sol";
import {SplitLiquidationCollateral} from "../contracts/SplitLiquidationCollateral.sol";
import {TestSetup} from "./utils/TestSetup.t.sol";

contract PositionManagerTest is TestSetup {
    uint256 public constant POSITIONS_SIZE = 10;

    PriceFeedTestnet public priceFeed;
    IPositionManager public positionManager;

    function setUp() public override {
        super.setUp();

        priceFeed = new PriceFeedTestnet();
        priceFeed.setPrice(1e18);
        positionManager = new PositionManager(
            new address[](0),
            splitLiquidationCollateral
        );
        positionManager.addCollateralToken(collateralToken, priceFeed, POSITIONS_SIZE);

        collateralToken.mint(ALICE, 10e36);
        collateralToken.mint(BOB, 10e36);
    }

    // --- Delegates ---

    function testGlobalDelegates() public {
        address[] memory globalDelegates = new address[](1);
        globalDelegates[0] = address(BOB);
        collateralToken.mint(ALICE, 10 ether);
        PositionManager positionManager2 = new PositionManager(
            globalDelegates,
            splitLiquidationCollateral
        );
        positionManager2.addCollateralToken(collateralToken, priceFeed, POSITIONS_SIZE);

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager2,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 collateralTopUpAmount = 1 ether;
        uint256 debtAmount = collateralTopUpAmount / 10;

        vm.startPrank(BOB);
        collateralToken.approve(address(positionManager2), collateralTopUpAmount);

        uint256 borrowerDebtBefore = positionManager2.raftDebtToken().balanceOf(ALICE);
        uint256 borrowerCollateralBefore = positionManager2.raftCollateralTokens(collateralToken).balanceOf(ALICE);
        uint256 borrowerRBalanceBefore = positionManager2.rToken().balanceOf(ALICE);
        uint256 borrowerCollateralBalanceBefore = collateralToken.balanceOf(ALICE);
        uint256 delegateRBalanceBefore = positionManager2.rToken().balanceOf(BOB);
        uint256 delegateCollateralBalanceBefore = collateralToken.balanceOf(BOB);
        positionManager2.managePosition(
            collateralToken, ALICE, collateralTopUpAmount, true, debtAmount, true, ALICE, ALICE, 0
        );
        uint256 borrowerRBalanceAfter = positionManager2.rToken().balanceOf(ALICE);
        uint256 borrowerCollateralBalanceAfter = collateralToken.balanceOf(ALICE);
        uint256 delegateRBalanceAfter = positionManager2.rToken().balanceOf(BOB);
        uint256 delegateCollateralBalanceAfter = collateralToken.balanceOf(BOB);
        uint256 borrowerDebtAfter = positionManager2.raftDebtToken().balanceOf(ALICE);
        uint256 borrowerCollateralAfter = positionManager2.raftCollateralTokens(collateralToken).balanceOf(ALICE);

        uint256 delegateDebtAfter = positionManager2.raftDebtToken().balanceOf(BOB);
        uint256 delegateCollateralAfter = positionManager2.raftCollateralTokens(collateralToken).balanceOf(BOB);

        assertEq(borrowerRBalanceAfter, borrowerRBalanceBefore + debtAmount);
        assertEq(borrowerCollateralBalanceAfter, borrowerCollateralBalanceBefore);
        assertEq(delegateRBalanceAfter, delegateRBalanceBefore);
        assertEq(delegateCollateralBalanceAfter, delegateCollateralBalanceBefore - collateralTopUpAmount);
        assertEq(borrowerDebtAfter - borrowerDebtBefore, debtAmount);
        assertEq(borrowerCollateralAfter - borrowerCollateralBefore, collateralTopUpAmount);
        assertEq(delegateDebtAfter, 0);
        assertEq(delegateCollateralAfter, 0);
    }

    function testIndividualDelegates() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        vm.prank(ALICE);
        positionManager.whitelistDelegate(BOB);

        uint256 collateralTopUpAmount = 1 ether;
        vm.startPrank(BOB);
        collateralToken.approve(address(positionManager), collateralTopUpAmount);
        positionManager.managePosition(collateralToken, ALICE, collateralTopUpAmount, true, 0, false, ALICE, ALICE, 0);
    }

    function testNonDelegateCannotManagePosition() public {
        uint256 collateralTopUpAmount = 1 ether;
        vm.startPrank(BOB);
        collateralToken.approve(address(positionManager), collateralTopUpAmount);

        vm.expectRevert(IPositionManager.DelegateNotWhitelisted.selector);
        positionManager.managePosition(collateralToken, ALICE, collateralTopUpAmount, true, 0, false, ALICE, ALICE, 0);
    }

    function testIndividualDelegateCannotManageOtherPositions() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        vm.prank(CAROL);
        positionManager.whitelistDelegate(BOB);

        uint256 collateralTopUpAmount = 1 ether;
        vm.prank(ALICE);
        collateralToken.approve(address(positionManager), collateralTopUpAmount);

        vm.prank(BOB);
        vm.expectRevert(IPositionManager.DelegateNotWhitelisted.selector);
        positionManager.managePosition(collateralToken, ALICE, collateralTopUpAmount, true, 0, false, ALICE, ALICE, 0);
    }

    // --- Borrowing Spread ---

    function testSetBorrowingSpread() public {
        positionManager.setBorrowingSpread(100);
        assertEq(positionManager.borrowingSpread(), 100);
    }

    function testUnauthorizedSetBorrowingSpread() public {
        vm.prank(ALICE);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        positionManager.setBorrowingSpread(100);
    }

    function testOutOfRangeSetBorrowingSpread() public {
        uint256 maxBorrowingSpread = positionManager.MAX_BORROWING_SPREAD();
        vm.expectRevert(IPositionManager.BorrowingSpreadExceedsMaximum.selector);
        positionManager.setBorrowingSpread(maxBorrowingSpread + 1);
    }

    // --- Redemption Spread ---

    function testSetRedemptionSpread() public {
        uint256 spread = positionManager.MIN_REDEMPTION_SPREAD() + 1;
        positionManager.setRedemptionSpread(spread);
        assertEq(positionManager.redemptionSpread(), spread);
    }

    function testUnauthorizedSetRedemptionSpread() public {
        vm.prank(ALICE);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        positionManager.setRedemptionSpread(100);
    }

    function testOutOfRangeSetRedemptionSpread() public {
        uint256 minRedemptionSpread = positionManager.MIN_REDEMPTION_SPREAD();
        vm.expectRevert(IPositionManager.RedemptionSpreadOutOfRange.selector);
        positionManager.setRedemptionSpread(minRedemptionSpread - 1);

        uint256 maxRedemptionSpread = positionManager.MAX_REDEMPTION_SPREAD();
        vm.expectRevert(IPositionManager.RedemptionSpreadOutOfRange.selector);
        positionManager.setRedemptionSpread(maxRedemptionSpread + 1);
    }

    // --- Split liquidation collateral ---
    function testSetSplitLiquidationCollateral() public {
        SplitLiquidationCollateral newSplitLiquidationCollateral = new SplitLiquidationCollateral();

        positionManager.setSplitLiquidationCollateral(newSplitLiquidationCollateral);
        assertEq(address(positionManager.splitLiquidationCollateral()), address(newSplitLiquidationCollateral));
    }

    function testCannotSetSplitLiquidationCollateral() public {
        vm.expectRevert(IPositionManager.SplitLiquidationCollateralCannotBeZero.selector);
        positionManager.setSplitLiquidationCollateral(SplitLiquidationCollateral(address(0)));

        SplitLiquidationCollateral newSplitLiquidationCollateral = new SplitLiquidationCollateral();
        vm.prank(ALICE);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        positionManager.setSplitLiquidationCollateral(newSplitLiquidationCollateral);
    }

    // --- Getters ---

    // Returns collateral
    function testGetPositionCollateral() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory alicePosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 150 * MathUtils._100_PERCENT / 100
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.OpenPositionResult memory bobPosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 150 * MathUtils._100_PERCENT / 100
        });
        vm.stopPrank();

        assertEq(positionManager.raftCollateralTokens(collateralToken).balanceOf(ALICE), alicePosition.collateral);
        assertEq(positionManager.raftCollateralTokens(collateralToken).balanceOf(BOB), bobPosition.collateral);
    }

    // Returns debt
    function testGetPositionDebt() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory alicePosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 150 * MathUtils._100_PERCENT / 100
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.OpenPositionResult memory bobPosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 150 * MathUtils._100_PERCENT / 100
        });
        vm.stopPrank();

        assertEq(positionManager.raftDebtToken().balanceOf(ALICE), alicePosition.totalDebt);
        assertEq(positionManager.raftDebtToken().balanceOf(BOB), bobPosition.totalDebt);
    }
}
