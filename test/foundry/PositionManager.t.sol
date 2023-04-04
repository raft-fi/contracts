// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../../contracts/PositionManager.sol";
import "./utils/PositionManagerUtils.sol";
import "./utils/TestSetup.t.sol";

contract PositionManagerTest is TestSetup {
    uint256 public constant POSITIONS_SIZE = 10;
    uint256 public constant LIQUIDATION_PROTOCOL_FEE = 0;

    PriceFeedTestnet public priceFeed;
    IPositionManager public positionManager;

    function setUp() public override {
        super.setUp();

        priceFeed = new PriceFeedTestnet();
        positionManager = new PositionManager(
            priceFeed,
            collateralToken,
            POSITIONS_SIZE,
            LIQUIDATION_PROTOCOL_FEE
        );

        collateralToken.mint(ALICE, 10e36);
        collateralToken.mint(BOB, 10e36);
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

    function testOutOfBoundsSetBorrowingSpread() public {
        uint256 maxBorrowingSpread = positionManager.MAX_BORROWING_SPREAD();
        vm.expectRevert(BorrowingSpreadExceedsMaximum.selector);
        positionManager.setBorrowingSpread(maxBorrowingSpread + 1);
    }

    // --- Getters ---

    // Returns stake
    function testGetPositionStake() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory alicePosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 150 * MathUtils._100pct / 100
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.OpenPositionResult memory bobPosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 150 * MathUtils._100pct / 100
        });
        vm.stopPrank();

        (,, uint256 aliceStake) = positionManager.positions(ALICE);
        (,, uint256 bobStake) = positionManager.positions(BOB);

        assertEq(aliceStake, alicePosition.collateral);
        assertEq(bobStake, bobPosition.collateral);
    }

    // Returns collateral
    function testGetPositionCollateral() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory alicePosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 150 * MathUtils._100pct / 100
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.OpenPositionResult memory bobPosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 150 * MathUtils._100pct / 100
        });
        vm.stopPrank();

        (, uint256 aliceCollateral,) = positionManager.positions(ALICE);
        (, uint256 bobCollateral,) = positionManager.positions(BOB);

        assertEq(aliceCollateral, alicePosition.collateral);
        assertEq(bobCollateral, bobPosition.collateral);
    }

    // Returns debt
    function testGetPositionDebt() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory alicePosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 150 * MathUtils._100pct / 100
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.OpenPositionResult memory bobPosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 150 * MathUtils._100pct / 100
        });
        vm.stopPrank();

        (uint256 aliceDebt,,) = positionManager.positions(ALICE);
        (uint256 bobDebt,,) = positionManager.positions(BOB);

        assertEq(aliceDebt, alicePosition.totalDebt);
        assertEq(bobDebt, bobPosition.totalDebt);
    }

    // Returns false it position is not active
    function testHasPendingRewards() public {
        assertFalse(positionManager.hasPendingRewards(ALICE));
    }
}
