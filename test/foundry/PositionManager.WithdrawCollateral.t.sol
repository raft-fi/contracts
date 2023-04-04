// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../../contracts/PositionManager.sol";
import "../TestContracts/PriceFeedTestnet.sol";
import "../TestContracts/WstETHTokenMock.sol";
import "./utils/PositionManagerUtils.sol";
import "./utils/TestSetup.t.sol";

contract PositionManagerWithdrawCollateralTest is TestSetup {
    uint256 public constant POSITIONS_SIZE = 10;
    uint256 public constant LIQUIDATION_PROTOCOL_FEE = 0;
    uint256 public constant DEFAULT_PRICE = 200e18;

    PriceFeedTestnet public priceFeed;
    IPositionManager public positionManager;

    function setUp() public {
        priceFeed = new PriceFeedTestnet();
        collateralToken = new WstETHTokenMock();
        positionManager = new PositionManager(
            priceFeed,
            collateralToken,
            POSITIONS_SIZE,
            LIQUIDATION_PROTOCOL_FEE
        );

        collateralToken.mint(ALICE, 10e36);
        collateralToken.mint(BOB, 10e36);
        collateralToken.mint(CAROL, 10e36);
        collateralToken.mint(DAVE, 10e36);
    }

    // Reverts when withdrawal would leave position with ICR < MCR
    function testInvalidICR() public {
        // Alice creates a position and adds first collateral
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
        positionManager.addColl(ALICE, ALICE, collateralTopUpAmount);
        vm.stopPrank();
    }

    // Reverts when calling address does not have active position
    function testNoActivePosition() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 10000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 10000e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Bob successfully withdraws some collateral
        vm.prank(BOB);
        positionManager.withdrawColl(0.1 ether, BOB, BOB);

        // Carol with no active position attempts to withdraw
        vm.prank(CAROL);
        vm.expectRevert(PositionManagerPositionNotActive.selector);
        positionManager.withdrawColl(1 ether, CAROL, CAROL);
    }

    // Reverts when requested collateral withdrawal is > the position's collateral
    function testWithdrawAmountExceedsCollateral() public {
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

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        (, uint256 bobCollateral,,) = positionManager.getEntireDebtAndColl(BOB);
        (, uint256 carolCollateral,,) = positionManager.getEntireDebtAndColl(CAROL);

        // Carol withdraws exactly all her collateral
        vm.prank(CAROL);
        vm.expectRevert(abi.encodeWithSelector(NewICRLowerThanMCR.selector, 0));
        positionManager.withdrawColl(carolCollateral, CAROL, CAROL);

        // Bob attempts to withdraw 1 wei more than his collateral
        vm.prank(BOB);
        vm.expectRevert(WithdrawingMoreThanAvailableCollateral.selector);
        positionManager.withdrawColl(bobCollateral + 1, BOB, BOB);
    }

    // Succeeds when borrowing rate = 0% and withdrawal would bring the user's ICR < MCR
    function testBorrowingRateZeroWithdrawalLowersICR() public {
        assertEq(positionManager.getBorrowingRate(), 0);

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 10e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: MathUtils.MCR
        });
        vm.stopPrank();

        // Bob attempts to withdraws 1 wei, which would leave him with < 110% ICR.
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(NewICRLowerThanMCR.selector, MathUtils.MCR - 1));
        positionManager.withdrawColl(1, BOB, BOB);
    }

    // Reverts when borrowing rate > 0% and withdrawal would bring the user's ICR < MCR
    function testBorrowingRateNonZeroWithdrawalLowersICR() public {
        positionManager.setBorrowingSpread(positionManager.MAX_BORROWING_SPREAD() / 2);
        assertGt(positionManager.getBorrowingRate(), 0);

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 10e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: MathUtils.MCR
        });
        vm.stopPrank();

        // Bob attempts to withdraws 1 wei, which would leave him with < 110% ICR.
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(NewICRLowerThanMCR.selector, MathUtils.MCR - 1));
        positionManager.withdrawColl(1, BOB, BOB);
    }

    // Doesn’t allow a user to completely withdraw all collateral from their position (due to gas compensation)
    function testDisallowedFullWithdrawal() public {
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

        (, uint256 aliceCollateral,,) = positionManager.getEntireDebtAndColl(ALICE);

        // Check position is active
        (bool alicePositionExistsBefore,,) = positionManager.sortedPositionsNodes(ALICE);
        assertTrue(alicePositionExistsBefore);

        // Alice attempts to withdraw all collateral
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(NewICRLowerThanMCR.selector, 0));
        positionManager.withdrawColl(aliceCollateral, ALICE, ALICE);
    }

    // Leaves the position active when the user withdraws less than all the collateral
    function testOpenPositionAfterPartialWithdrawal() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        // Check position is active
        (bool alicePositionExistsBefore,,) = positionManager.sortedPositionsNodes(ALICE);
        assertTrue(alicePositionExistsBefore);

        // Alice withdraws some collateral
        vm.prank(ALICE);
        positionManager.withdrawColl(1e17, ALICE, ALICE);

        // Check position is still active
        (bool alicePositionExistsAfter,,) = positionManager.sortedPositionsNodes(ALICE);
        assertTrue(alicePositionExistsAfter);
    }

    // Reduces the position's collateral by the correct amount
    function testPositionCollateralReduction() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        (, uint256 aliceCollateralBefore,,) = positionManager.getEntireDebtAndColl(ALICE);

        uint256 withdrawAmount = 1 ether;

        // Alice withdraws 1 ether
        vm.prank(ALICE);
        positionManager.withdrawColl(withdrawAmount, ALICE, ALICE);

        // Check 1 ether remaining
        (, uint256 aliceCollateralAfter,,) = positionManager.getEntireDebtAndColl(ALICE);

        assertEq(aliceCollateralAfter, aliceCollateralBefore - withdrawAmount);
    }

    // Reduces position manager's collateral by correct amount
    function testPositionManagerCollateralReduction() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 positionManagerBalance = collateralToken.balanceOf(address(positionManager));
        uint256 withdrawAmount = 1 ether;

        vm.prank(ALICE);
        positionManager.withdrawColl(withdrawAmount, ALICE, ALICE);

        uint256 positionManagerBalanceAfter = collateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerBalanceAfter, positionManagerBalance - withdrawAmount);
    }

    // Updates the stake and updates the total stakes
    function testStakeUpdate() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 0,
            icr: 2e18,
            amount: 5 ether
        });
        vm.stopPrank();

        (, uint256 aliceCollateralBefore,,) = positionManager.getEntireDebtAndColl(ALICE);
        assertGt(aliceCollateralBefore, 0);

        (,, uint256 aliceStakeBefore) = positionManager.positions(ALICE);
        uint256 totalStakesBefore = positionManager.totalStakes();
        assertEq(aliceStakeBefore, aliceCollateralBefore);
        assertEq(totalStakesBefore, aliceCollateralBefore);

        uint256 withdrawAmount = 1 ether;

        // Alice withdraws 1 ether
        vm.prank(ALICE);
        positionManager.withdrawColl(withdrawAmount, ALICE, ALICE);

        // Check stake and total stakes get updated
        (,, uint256 aliceStakeAfter) = positionManager.positions(ALICE);
        uint256 totalStakesAfter = positionManager.totalStakes();
        assertEq(aliceStakeAfter, aliceStakeBefore - withdrawAmount);
        assertEq(totalStakesAfter, totalStakesBefore - withdrawAmount);
    }

    // Sends the correct amount of collateral to the user
    function testCollateralTransfer() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 0,
            icr: 2e18,
            amount: 2 ether
        });
        vm.stopPrank();

        uint256 aliceBalanceBefore = collateralToken.balanceOf(ALICE);
        uint256 withdrawAmount = 1 ether;

        // Alice withdraws 1 ether
        vm.prank(ALICE);
        positionManager.withdrawColl(withdrawAmount, ALICE, ALICE);

        uint256 aliceBalanceAfter = collateralToken.balanceOf(ALICE);
        assertEq(aliceBalanceAfter, aliceBalanceBefore + withdrawAmount);
    }

    // Applies pending rewards and updates user's L_CollateralBalance, L_RDebt snapshots
    function testPendingRewardsAndSnapshots() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 10e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 0,
            icr: 3e18,
            amount: 100 ether
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 0,
            icr: 3e18,
            amount: 10 ether
        });
        vm.stopPrank();

        vm.startPrank(DAVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 0,
            icr: 2e18,
            amount: 10 ether
        });
        vm.stopPrank();

        CollateralDebt memory bobBalanceBefore;
        (bobBalanceBefore.debt, bobBalanceBefore.collateral,,) = positionManager.getEntireDebtAndColl(BOB);
        CollateralDebt memory carolBalanceBefore;
        (carolBalanceBefore.debt, carolBalanceBefore.collateral,,) = positionManager.getEntireDebtAndColl(CAROL);

        // price drops to 1ETH:100R, reducing Dave's ICR below MCR
        priceFeed.setPrice(100e18);

        // close Dave's Position, liquidating 1 ether and 180R.
        positionManager.liquidate(DAVE);

        CollateralDebt memory lBalance;
        lBalance.collateral = positionManager.L_CollateralBalance();
        lBalance.debt = positionManager.L_RDebt();

        // check Bob and Carol's reward snapshots are zero before they alter their positions
        CollateralDebt memory bobRewardSnapshotBefore;
        (bobRewardSnapshotBefore.collateral, bobRewardSnapshotBefore.debt) = positionManager.rewardSnapshots(BOB);
        CollateralDebt memory carolRewardSnapshotBefore;
        (carolRewardSnapshotBefore.collateral, carolRewardSnapshotBefore.debt) = positionManager.rewardSnapshots(CAROL);
        assertEq(bobRewardSnapshotBefore.collateral, 0);
        assertEq(bobRewardSnapshotBefore.debt, 0);
        assertEq(carolRewardSnapshotBefore.collateral, 0);
        assertEq(carolRewardSnapshotBefore.debt, 0);

        // Check Bob and Carol have pending rewards
        CollateralDebt memory bobPendingReward;
        bobPendingReward.collateral = positionManager.getPendingCollateralTokenReward(BOB);
        bobPendingReward.debt = positionManager.getPendingRDebtReward(BOB);
        CollateralDebt memory carolPendingReward;
        carolPendingReward.collateral = positionManager.getPendingCollateralTokenReward(CAROL);
        carolPendingReward.debt = positionManager.getPendingRDebtReward(CAROL);
        assertGt(bobPendingReward.collateral, 0);
        assertGt(bobPendingReward.debt, 0);
        assertGt(carolPendingReward.collateral, 0);
        assertGt(carolPendingReward.debt, 0);

        uint256 bobWithdrawAmount = 5 ether;
        uint256 carolWithdrawAmount = 1 ether;

        // Bob and Carol withdraw from their positions
        vm.prank(BOB);
        positionManager.withdrawColl(bobWithdrawAmount, BOB, BOB);
        vm.prank(CAROL);
        positionManager.withdrawColl(carolWithdrawAmount, CAROL, CAROL);

        // Check that both alice and Bob have had pending rewards applied in addition to their top-ups
        CollateralDebt memory bobBalanceAfter;
        (bobBalanceAfter.debt, bobBalanceAfter.collateral,,) = positionManager.getEntireDebtAndColl(BOB);
        CollateralDebt memory carolBalanceAfter;
        (carolBalanceAfter.debt, carolBalanceAfter.collateral,,) = positionManager.getEntireDebtAndColl(CAROL);

        // Check rewards have been applied to positions
        assertEq(
            bobBalanceAfter.collateral, bobBalanceBefore.collateral + bobPendingReward.collateral - bobWithdrawAmount
        );
        assertEq(bobBalanceAfter.debt, bobBalanceBefore.debt + bobPendingReward.debt);
        assertEq(
            carolBalanceAfter.collateral,
            carolBalanceBefore.collateral + carolPendingReward.collateral - carolWithdrawAmount
        );
        assertEq(carolBalanceAfter.debt, carolBalanceBefore.debt + carolPendingReward.debt);

        // After top up, both Alice and Bob's snapshots of the rewards-per-unit-staked metrics should be updated
        // to the latest values of L_CollateralBalance and L_RDebt
        CollateralDebt memory bobRewardSnapshotAfter;
        (bobRewardSnapshotAfter.collateral, bobRewardSnapshotAfter.debt) = positionManager.rewardSnapshots(BOB);
        CollateralDebt memory carolRewardSnapshotAfter;
        (carolRewardSnapshotAfter.collateral, carolRewardSnapshotAfter.debt) = positionManager.rewardSnapshots(CAROL);

        assertEq(bobRewardSnapshotAfter.collateral, lBalance.collateral);
        assertEq(bobRewardSnapshotAfter.debt, lBalance.debt);
        assertEq(carolRewardSnapshotAfter.collateral, lBalance.collateral);
        assertEq(carolRewardSnapshotAfter.debt, lBalance.debt);
    }
}
