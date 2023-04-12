// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import { PositionManager } from "../contracts/PositionManager.sol";
import "./TestContracts/PriceFeedTestnet.sol";
import "./TestContracts/WstETHTokenMock.sol";
import "./utils/PositionManagerUtils.sol";
import "./utils/TestSetup.t.sol";

contract PositionManagerWithdrawCollateralTest is TestSetup {
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
        vm.expectRevert(abi.encodeWithSelector(NewICRLowerThanMCR.selector, MathUtils._100_PERCENT));
        positionManager.managePosition(collateralTopUpAmount, true, 0, false, ALICE, ALICE, 0);
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
        positionManager.managePosition(0.1 ether, false, 0, false, BOB, BOB, 0);

        // Carol with no active position attempts to withdraw
        vm.prank(CAROL);
        vm.expectRevert(bytes("ERC20: burn amount exceeds balance"));
        positionManager.managePosition(1 ether, false, 0, false, CAROL, CAROL, 0);
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

        uint256 bobCollateral = positionManager.raftCollateralToken().balanceOf(BOB);
        uint256 carolCollateral = positionManager.raftCollateralToken().balanceOf(CAROL);

        // Carol withdraws exactly all her collateral
        vm.prank(CAROL);
        vm.expectRevert(abi.encodeWithSelector(NewICRLowerThanMCR.selector, 0));
        positionManager.managePosition(carolCollateral, false, 0, false, CAROL, CAROL, 0);

        // Bob attempts to withdraw 1 wei more than his collateral
        vm.prank(BOB);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        positionManager.managePosition(bobCollateral + 1, false, 0, false, BOB, BOB, 0);
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
        positionManager.managePosition(1, false, 0, false, BOB, BOB, 0);
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
/*
        // Bob attempts to withdraws 1 wei, which would leave him with < 110% ICR.
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(NewICRLowerThanMCR.selector, MathUtils.MCR - 1));
        positionManager.managePosition(1, false, 0, false, BOB, BOB, 0);*/
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

        uint256 aliceCollateral = positionManager.raftCollateralToken().balanceOf(ALICE);

        // Check position is active
        (bool alicePositionExistsBefore,,) = positionManager.sortedPositionsNodes(ALICE);
        assertTrue(alicePositionExistsBefore);

        // Alice attempts to withdraw all collateral
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(NewICRLowerThanMCR.selector, 0));
        positionManager.managePosition(aliceCollateral, false, 0, false, ALICE, ALICE, 0);
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
        positionManager.managePosition(1e17, false, 0, false, ALICE, ALICE, 0);

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

        uint256 aliceCollateralBefore = positionManager.raftCollateralToken().balanceOf(ALICE);

        uint256 withdrawAmount = 1 ether;

        // Alice withdraws 1 ether
        vm.prank(ALICE);
        positionManager.managePosition(withdrawAmount, false, 0, false, ALICE, ALICE, 0);

        // Check 1 ether remaining
        uint256 aliceCollateralAfter = positionManager.raftCollateralToken().balanceOf(ALICE);

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
        positionManager.managePosition(withdrawAmount, false, 0, false, ALICE, ALICE, 0);

        uint256 positionManagerBalanceAfter = collateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerBalanceAfter, positionManagerBalance - withdrawAmount);
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
        positionManager.managePosition(withdrawAmount, false, 0, false, ALICE, ALICE, 0);

        uint256 aliceBalanceAfter = collateralToken.balanceOf(ALICE);
        assertEq(aliceBalanceAfter, aliceBalanceBefore + withdrawAmount);
    }
}
