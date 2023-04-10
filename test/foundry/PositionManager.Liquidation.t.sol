// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../../contracts/PositionManager.sol";
import "../TestContracts/PriceFeedTestnet.sol";
import "../TestContracts/WstETHTokenMock.sol";
import "./utils/PositionManagerUtils.sol";
import "./utils/TestSetup.t.sol";

contract PositionManagerLiquidationTest is TestSetup {
    uint256 public constant POSITIONS_SIZE = 10;
    uint256 public constant LIQUIDATION_PROTOCOL_FEE = 0;

    PriceFeedTestnet public priceFeed;
    IPositionManager public positionManager;
    IRToken public rToken;

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
        rToken = positionManager.rToken();

        collateralToken.mint(ALICE, 10e36);
        collateralToken.mint(BOB, 10e36);
        collateralToken.mint(CAROL, 10e36);
        collateralToken.mint(DAVE, 10e36);
        collateralToken.mint(EVE, 10e36);
    }

    // Closes a position that has ICR < MCR
    function testSuccessfulPositionLiquidation() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 20e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 4e18
        });
        vm.stopPrank();

        uint256 price = priceFeed.getPrice();

        uint256 icrBefore = positionManager.getCurrentICR(BOB, price);
        assertEq(icrBefore, 4e18);

        // Bob increases debt to 180 R, lowering his ICR to 1.11
        uint256 targetICR = 1111111111111111111;
        vm.startPrank(BOB);
        PositionManagerUtils.withdrawR({
            positionManager: positionManager,
            priceFeed: priceFeed,
            borrower: BOB,
            icr: targetICR
        });
        vm.stopPrank();

        uint256 icrAfter = positionManager.getCurrentICR(BOB, price);
        assertEq(icrAfter, targetICR);

        // price drops to 1ETH:100R, reducing Bob's ICR below MCR
        priceFeed.setPrice(100e18);

        // liquidate position
        positionManager.liquidate(BOB);

        // Bob's position is closed
        (bool bobPositionExists,,) = positionManager.sortedPositionsNodes(BOB);
        assertFalse(bobPositionExists);
    }

    // Removes the position's stake from the total stakes and updates snapshots of total stakes and total collateral
    function testPositionStakeRemovalSnapshotUpdates() public {
        vm.prank(address(positionManager));
        rToken.mint(address(this), 1_000_000e18);

        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory alicePosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 4e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.OpenPositionResult memory bobPosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        // Check total stakes before
        uint256 totalStakesBefore = positionManager.totalStakes();
        assertEq(totalStakesBefore, alicePosition.collateral + bobPosition.collateral);

        // Check snapshots before
        uint256 totalStakesSnapshotBefore = positionManager.totalStakesSnapshot();
        uint256 totalCollateralSnapshotBefore = positionManager.totalCollateralSnapshot();
        assertEq(totalStakesSnapshotBefore, 0);
        assertEq(totalCollateralSnapshotBefore, 0);

        // Price drops to 1ETH:100R, reducing Bob's ICR below MCR
        priceFeed.setPrice(100e18);

        // Close Bob's Position
        positionManager.liquidate(BOB);

        // Check total stakes after
        uint256 totalStakesAfter = positionManager.totalStakes();
        assertEq(totalStakesAfter, alicePosition.collateral);

        /* Check snapshots after. Total stakes should be equal to the remaining stake then the system:
        10 ether, Alice's stake.

        Total collateral should be equal to Alice's collateral plus her pending ETH reward
        (Bob’s collateral * (1 - collateral gas compensation)), earned from the liquidation of Bob's Position. */
        uint256 totalStakesSnapshotAfter = positionManager.totalStakesSnapshot();
        uint256 totalCollateralSnapshotAfter = positionManager.totalCollateralSnapshot();

        assertEq(totalStakesSnapshotAfter, alicePosition.collateral);
        assertEq(
            totalCollateralSnapshotAfter,
            alicePosition.collateral + PositionManagerUtils.applyLiquidationFee(positionManager, bobPosition.collateral)
        );
    }

    // Updates the L_CollateralBalance and L_RDebt reward-per-unit-staked totals
    function testLCollateralDebtBalanceUpdate() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory alicePosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 8e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.OpenPositionResult memory bobPosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 4e18
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.OpenPositionResult memory carolPosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 1.11e18
        });
        vm.stopPrank();

        // Price drops to 1ETH:100R, reducing Carols's ICR below MCR
        priceFeed.setPrice(100e18);

        // Close Carol's position
        positionManager.liquidate(CAROL);
        (bool carolPositionExists,,) = positionManager.sortedPositionsNodes(CAROL);
        assertFalse(carolPositionExists);

        uint256 lCollateralAfterCarolLiquidated = positionManager.L_CollateralBalance();
        uint256 lRDebtAfterCarolLiquidated = positionManager.L_RDebt();

        uint256 lCollateralExpected = PositionManagerUtils.applyLiquidationFee(
            positionManager, carolPosition.collateral
        ) * 1e18 / (alicePosition.collateral + bobPosition.collateral);
        uint256 lRDebtExpected = carolPosition.totalDebt * 1e18 / (alicePosition.collateral + bobPosition.collateral);
        assertEq(lCollateralAfterCarolLiquidated, lCollateralExpected);
        assertEq(lRDebtAfterCarolLiquidated, lRDebtExpected);

        // Bob now withdraws R, bringing his ICR to 1.11
        vm.startPrank(BOB);
        PositionManagerUtils.WithdrawRResult memory bobWithdrawal = PositionManagerUtils.withdrawR({
            positionManager: positionManager,
            priceFeed: priceFeed,
            borrower: BOB,
            icr: 1.11e18
        });
        vm.stopPrank();

        // Price drops to 1ETH:50R, reducing Bob's ICR below MCR
        priceFeed.setPrice(50e18);

        // Close Bob's Position
        positionManager.liquidate(BOB);
        (bool bobPositionExists,,) = positionManager.sortedPositionsNodes(BOB);
        assertFalse(bobPositionExists);

        /* Alice now has all the active stake. Total stakes in the system is now 10 ether.

        Bob's pending collateral reward and debt reward are applied to his position
        before his liquidation.

        The system rewards-per-unit-staked should now be:

        L_CollateralBalance = (0.995 / 20) + (10.4975 * 0.995 / 10) = 1.09425125 ETH
        L_RDebt = (180 / 20) + (890 / 10) = 98 R */
        uint256 lCollateralAfterBobLiquidated = positionManager.L_CollateralBalance();
        uint256 lRDebtAfterBobLiquidated = positionManager.L_RDebt();

        lCollateralExpected += PositionManagerUtils.applyLiquidationFee(
            positionManager, bobPosition.collateral + bobPosition.collateral * lCollateralExpected / 1e18
        ) * 1e18 / alicePosition.collateral;
        lRDebtExpected += (
            bobPosition.totalDebt + bobWithdrawal.increasedTotalDebt + bobPosition.collateral * lRDebtExpected / 1e18
        ) * 1e18 / alicePosition.collateral;
        assertLt(lCollateralAfterBobLiquidated - lCollateralExpected, 100);
        assertLt(lRDebtAfterBobLiquidated - lRDebtExpected, 100);
    }

    // Liquidates undercollateralized position if there are two positions in the system
    function testSuccessfulLiquidationTwoPositionsSystem() public {
        vm.prank(address(positionManager));
        rToken.mint(address(this), 1_000_000e18);

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 0,
            icr: 200e18,
            amount: 100 ether
        });
        vm.stopPrank();

        // Alice creates a single position with 0.7 ETH and a debt of 70 R
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        // Set ETH:USD price to 105
        priceFeed.setPrice(105e18);
        uint256 price = priceFeed.getPrice();

        uint256 aliceICR = positionManager.getCurrentICR(ALICE, price);
        assertEq(aliceICR, 105 * MathUtils._100pct / 100);

        // Liquidate the position
        positionManager.liquidate(ALICE);

        (bool alicePositionExists,,) = positionManager.sortedPositionsNodes(ALICE);
        assertFalse(alicePositionExists);

        (bool bobPositionExists,,) = positionManager.sortedPositionsNodes(BOB);
        assertTrue(bobPositionExists);
    }

    // Reverts if position is non-existent or has been closed
    function testLiquidateNonExistentPosition() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 4e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2.1e18
        });
        vm.stopPrank();

        (bool carolPositionExists,,) = positionManager.sortedPositionsNodes(CAROL);
        assertFalse(carolPositionExists);

        vm.expectRevert(PositionManagerPositionNotActive.selector);
        positionManager.liquidate(CAROL);

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        (bool carolPositionExistsBeforeLiquidation,,) = positionManager.sortedPositionsNodes(CAROL);
        assertTrue(carolPositionExistsBeforeLiquidation);

        // Price drops, Carol ICR falls below MCR
        priceFeed.setPrice(100e18);

        // Carol liquidated, and her position is closed
        positionManager.liquidate(CAROL);

        (bool carolPositionExistsAfterLiquidation,,) = positionManager.sortedPositionsNodes(CAROL);
        assertFalse(carolPositionExistsAfterLiquidation);

        vm.expectRevert(PositionManagerPositionNotActive.selector);
        positionManager.liquidate(CAROL);
    }

    // Does nothing if position has >= 110% ICR
    function testInvalidLiquidationProperICR() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 3e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 3e18
        });
        vm.stopPrank();

        (,,, uint256 listSizeBefore) = positionManager.sortedPositions();
        uint256 price = priceFeed.getPrice();

        // Check Bob's ICR > 110%
        uint256 bobICR = positionManager.getCurrentICR(BOB, price);
        assertTrue(bobICR >= MathUtils.MCR);

        // Attempt to liquidate Bob
        vm.expectRevert(NothingToLiquidate.selector);
        positionManager.liquidate(BOB);

        // Check Bob active, check Alice active
        (bool bobPositionExists,,) = positionManager.sortedPositionsNodes(BOB);
        assertTrue(bobPositionExists);
        (bool alicePositionExists,,) = positionManager.sortedPositionsNodes(ALICE);
        assertTrue(alicePositionExists);

        (,,, uint256 listSizeAfter) = positionManager.sortedPositions();
        assertEq(listSizeBefore, listSizeAfter);
    }

    // Liquidates based on entire collateral/debt (including pending rewards), not raw collateral/debt
    function testEntireCollateralDebtLiquidation() public {
        vm.prank(address(positionManager));
        rToken.mint(address(this), 1_000_000e18);

        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory alicePosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 100e18,
            icr: 8e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.OpenPositionResult memory bobPosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 100e18,
            icr: 2.21e18
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.OpenPositionResult memory carolPosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 100e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Dave opens with 60 R, 0.6 ETH
        vm.startPrank(DAVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        // Price drops
        priceFeed.setPrice(100e18);
        uint256 price = priceFeed.getPrice();

        uint256 aliceICRBefore = positionManager.getCurrentICR(ALICE, price);
        uint256 bobICRBefore = positionManager.getCurrentICR(BOB, price);
        uint256 carolICRBefore = positionManager.getCurrentICR(CAROL, price);

        /* Before liquidation:
        Alice ICR: 2 * 100 / 50 = 400%
        Bob ICR: 1 * 100 / 90.5 = 110.5%
        Carol ICR: 1 * 100 / 100 = 100%

        Therefore Alice and Bob above the MCR, Carol is below */
        assertGe(aliceICRBefore, MathUtils.MCR);
        assertGe(bobICRBefore, MathUtils.MCR);
        assertLe(carolICRBefore, MathUtils.MCR);

        /* Liquidate Dave. 30 R and 0.3 ETH is distributed between Alice, Bob and Carol.

        Alice receives (30 * 2/4) = 15 R, and (0.3 * 2/4) = 0.15 ETH
        Bob receives (30 * 1/4) = 7.5 R, and (0.3 * 1/4) = 0.075 ETH
        Carol receives (30 * 1/4) = 7.5 R, and (0.3 * 1/4) = 0.075 ETH
        */
        positionManager.liquidate(DAVE);

        uint256 aliceICRAfter = positionManager.getCurrentICR(ALICE, price);
        uint256 bobICRAfter = positionManager.getCurrentICR(BOB, price);
        uint256 carolICRAfter = positionManager.getCurrentICR(CAROL, price);

        /* After liquidation:

        Alice ICR: 10.15 * 100 / 60 = 183.33%
        Bob ICR: 1.075 * 100 / 98 = 109.69%
        Carol ICR: 1.075 * 100 / 107.5 = 100.0%

        Check Alice is above MCR, Bob below, Carol below. */
        assertGe(aliceICRAfter, MathUtils.MCR);
        assertLe(bobICRAfter, MathUtils.MCR);
        assertLe(carolICRAfter, MathUtils.MCR);

        /* Though Bob's true ICR (including pending rewards) is below the MCR,
        check that Bob's raw coll and debt has not changed, and that his "raw" ICR is above the MCR */
        (uint256 bobDebt, uint256 bobCollateral,) = positionManager.positions(BOB);

        uint256 bobRawICR = bobCollateral * price / bobDebt;
        assertGe(bobRawICR, MathUtils.MCR);

        vm.startPrank(EVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 20e18
        });
        vm.stopPrank();

        // Check list size
        (,,, uint256 listSizeBefore) = positionManager.sortedPositions();
        assertEq(listSizeBefore, 4);

        // Liquidate Alice unsuccessfully and Bob and Carol successfully
        vm.expectRevert(NothingToLiquidate.selector);
        positionManager.liquidate(ALICE);
        positionManager.liquidate(BOB);
        positionManager.liquidate(CAROL);

        // Check list size reduced to 2
        (,,, uint256 listSizeAfter) = positionManager.sortedPositions();
        assertEq(listSizeAfter, 2);

        /* Check Alice stays active, Carol gets liquidated, and Bob gets liquidated
        (because his pending rewards bring his ICR < MCR) */
        (bool alicePositionExists,,) = positionManager.sortedPositionsNodes(ALICE);
        assertTrue(alicePositionExists);
        (bool bobPositionExists,,) = positionManager.sortedPositionsNodes(BOB);
        assertFalse(bobPositionExists);
        (bool carolPositionExists,,) = positionManager.sortedPositionsNodes(CAROL);
        assertFalse(carolPositionExists);

        // Confirm token balances have not changed
        assertEq(rToken.balanceOf(ALICE), alicePosition.rAmount);
        assertEq(rToken.balanceOf(BOB), bobPosition.rAmount);
        assertEq(rToken.balanceOf(CAROL), carolPosition.rAmount);
    }
}
