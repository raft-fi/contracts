// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../../contracts/PositionManager.sol";
import "../TestContracts/PriceFeedTestnet.sol";
import "../TestContracts/WstETHTokenMock.sol";
import "./utils/PositionManagerUtils.sol";
import "./utils/TestSetup.t.sol";

contract PositionManagerAddCollateralTest is TestSetup {
    uint256 public constant POSITIONS_SIZE = 10;
    uint256 public constant LIQUIDATION_PROTOCOL_FEE = 0;
    uint256 public constant DEFAULT_PRICE = 200e18;

    PriceFeedTestnet public priceFeed;
    IPositionManager public positionManager;

    function setUp() public override {
        super.setUp();

        priceFeed = new PriceFeedTestnet();
        positionManager = new PositionManager(
            priceFeed,
            collateralToken,
            POSITIONS_SIZE,
            LIQUIDATION_PROTOCOL_FEE,
            new address[](0)
        );

        collateralToken.mint(ALICE, 10e36);
        collateralToken.mint(BOB, 10e36);
        collateralToken.mint(CAROL, 10e36);
    }

    // reverts when top-up would leave position with ICR < MCR
    function testInvalidICR() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 10e18
        });
        vm.stopPrank();

        // Price drops
        priceFeed.setPrice(100e18);
        uint256 price = priceFeed.getPrice();

        assertLt(positionManager.getCurrentICR(ALICE, price), MathUtils.MCR);

        uint256 collateralTopUpAmount = 1;

        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), collateralTopUpAmount);
        vm.expectRevert(abi.encodeWithSelector(NewICRLowerThanMCR.selector, MathUtils._100pct));
        positionManager.managePosition(collateralTopUpAmount, true, 0, false, ALICE, ALICE, 0);
        vm.stopPrank();
    }

    // Increases the position manager's collateral token balance by correct amount
    function testPositionManagerBalanceIncrease() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory result = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 positionManagerBalanceBefore = collateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerBalanceBefore, result.collateral);

        uint256 collateralTopUpAmount = 1 ether;

        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), collateralTopUpAmount);
        positionManager.managePosition(collateralTopUpAmount, true, 0, false, ALICE, ALICE, 0);
        vm.stopPrank();

        uint256 positionManagerBalanceAfter = collateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerBalanceAfter, positionManagerBalanceBefore + collateralTopUpAmount);
    }

    // Active position: adds the correct collateral amount to the position
    function testPositionCollateralIncrease() public {
        // Alice creates a position and adds first collateral
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        (, uint256 positionCollateralBefore,) = positionManager.positions(ALICE);

        uint256 collateralTopUpAmount = 1 ether;

        // Alice adds second collateral
        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), collateralTopUpAmount);
        positionManager.managePosition(collateralTopUpAmount, true, 0, false, ALICE, ALICE, 0);
        vm.stopPrank();

        (, uint256 positionCollateralAfter,) = positionManager.positions(ALICE);

        assertEq(positionCollateralAfter, positionCollateralBefore + collateralTopUpAmount);
    }

    // Active position: position is in the sorted list before and after
    function testPositionInSortedList() public {
        // Alice creates a position and adds first collateral
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        // check Alice is in the list before
        (bool alicePositionInListBefore,,) = positionManager.sortedPositionsNodes(ALICE);
        (,,, uint256 listSizeBefore) = positionManager.sortedPositions();
        assertTrue(alicePositionInListBefore);
        assertGt(listSizeBefore, 0);

        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), 1e18);
        positionManager.managePosition(1e18, true, 0, false, ALICE, ALICE, 0);
        vm.stopPrank();

        // check Alice is still in the list after
        (bool alicePositionInListAfter,,) = positionManager.sortedPositionsNodes(ALICE);
        (,,, uint256 listSizeAfter) = positionManager.sortedPositions();
        assertTrue(alicePositionInListAfter);
        assertGt(listSizeAfter, 0);
    }

    // Active position: updates the stake and updates the total stakes
    function testStakeUpdate() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        (,, uint256 aliceStakeBefore) = positionManager.positions(ALICE);
        uint256 totalStakesBefore = positionManager.totalStakes();

        assertEq(totalStakesBefore, aliceStakeBefore);

        uint256 collateralTopUpAmount = 2 ether;

        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), collateralTopUpAmount);
        positionManager.managePosition(collateralTopUpAmount, true, 0, false, ALICE, ALICE, 0);
        vm.stopPrank();

        (,, uint256 aliceStakeAfter) = positionManager.positions(ALICE);
        uint256 totalStakesAfter = positionManager.totalStakes();

        assertEq(aliceStakeAfter, aliceStakeBefore + collateralTopUpAmount);
        assertEq(totalStakesAfter, totalStakesBefore + collateralTopUpAmount);
    }

    // Active position: applies pending rewards and updates user's L_CollateralBalance, L_RDebt snapshots
    function testPendingRewardsAndSnapshots() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory alicePosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 15000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.OpenPositionResult memory bobPosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 10000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 5000e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Price drops to 1ETH:100R, reducing Carol's ICR below MCR
        priceFeed.setPrice(100e18);

        // Liquidate Carol's Position
        positionManager.liquidate(CAROL);

        priceFeed.setPrice(DEFAULT_PRICE);

        (bool carolPositionExists,,) = positionManager.sortedPositionsNodes(CAROL);
        assertFalse(carolPositionExists);

        CollateralDebt memory lBalance;
        lBalance.collateral = positionManager.L_CollateralBalance();
        lBalance.debt = positionManager.L_RDebt();

        // Check Alice and Bob's reward snapshots are zero before they alter their positions
        (uint256 aliceCollateralSnapshotBefore, uint256 aliceRDebtSnapshotBefore) =
            positionManager.rewardSnapshots(ALICE);
        (uint256 bobCollateralSnapshotBefore, uint256 bobRDebtSnapshotBefore) = positionManager.rewardSnapshots(BOB);
        assertEq(aliceCollateralSnapshotBefore, 0);
        assertEq(aliceRDebtSnapshotBefore, 0);
        assertEq(bobCollateralSnapshotBefore, 0);
        assertEq(bobRDebtSnapshotBefore, 0);

        CollateralDebt memory alicePendingRewards;
        alicePendingRewards.collateral = positionManager.getPendingCollateralTokenReward(ALICE);
        alicePendingRewards.debt = positionManager.getPendingRDebtReward(ALICE);
        CollateralDebt memory bobPendingRewards;
        bobPendingRewards.collateral = positionManager.getPendingCollateralTokenReward(BOB);
        bobPendingRewards.debt = positionManager.getPendingRDebtReward(BOB);
        assertGt(alicePendingRewards.collateral, 0);
        assertGt(alicePendingRewards.debt, 0);
        assertGt(bobPendingRewards.collateral, 0);
        assertGt(bobPendingRewards.debt, 0);

        // Alice and Bob top up their Positions

        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), 5 ether);
        positionManager.managePosition(5 ether, true, 0, false, ALICE, ALICE, 0);
        vm.stopPrank();

        vm.startPrank(BOB);
        collateralToken.approve(address(positionManager), 1 ether);
        positionManager.managePosition(1 ether, true, 0, false, BOB, BOB, 0);
        vm.stopPrank();

        // Check that both alice and Bob have had pending rewards applied in addition to their top-ups
        CollateralDebt memory aliceNewBalance;
        (aliceNewBalance.debt, aliceNewBalance.collateral,,) = positionManager.getEntireDebtAndColl(ALICE);
        CollateralDebt memory bobNewBalance;
        (bobNewBalance.debt, bobNewBalance.collateral,,) = positionManager.getEntireDebtAndColl(BOB);

        assertEq(aliceNewBalance.collateral, alicePosition.collateral + alicePendingRewards.collateral + 5 ether);
        assertEq(aliceNewBalance.debt, alicePosition.totalDebt + alicePendingRewards.debt);
        assertEq(bobNewBalance.collateral, bobPosition.collateral + bobPendingRewards.collateral + 1 ether);
        assertEq(bobNewBalance.debt, bobPosition.totalDebt + bobPendingRewards.debt);

        // Check that both Alice and Bob's snapshots of the rewards-per-unit-staked metrics should be updated
        // to the latest values of L_CollateralBalance and L_RDebt
        CollateralDebt memory aliceSnapshotAfter;
        (aliceSnapshotAfter.collateral, aliceSnapshotAfter.debt) = positionManager.rewardSnapshots(ALICE);
        CollateralDebt memory bobSnapshotAfter;
        (bobSnapshotAfter.collateral, bobSnapshotAfter.debt) = positionManager.rewardSnapshots(BOB);

        assertEq(aliceSnapshotAfter.collateral, lBalance.collateral);
        assertEq(aliceSnapshotAfter.debt, lBalance.debt);
        assertEq(bobSnapshotAfter.collateral, lBalance.collateral);
        assertEq(bobSnapshotAfter.debt, lBalance.debt);
    }

    // Reverts if position is non-existent or closed
    function testInvalidPosition() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        // Carol attempts to add collateral to her non-existent position
        vm.startPrank(CAROL);
        collateralToken.approve(address(positionManager), 1 ether);
        vm.expectRevert(PositionManagerPositionNotActive.selector);
        positionManager.managePosition(1 ether, true, 0, false, CAROL, CAROL, 0);
        vm.stopPrank();

        // Price drops
        priceFeed.setPrice(100e18);

        // Bob gets liquidated
        positionManager.liquidate(BOB);

        (bool bobPositionExists,,) = positionManager.sortedPositionsNodes(BOB);
        assertFalse(bobPositionExists);

        // Bob attempts to add collateral to his closed position
        vm.startPrank(BOB);
        collateralToken.approve(address(positionManager), 1 ether);
        vm.expectRevert(PositionManagerPositionNotActive.selector);
        positionManager.managePosition(1 ether, true, 0, false, BOB, BOB, 0);
        vm.stopPrank();
    }
}
