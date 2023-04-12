// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../contracts/PositionManager.sol";
import "./TestContracts/PriceFeedTestnet.sol";
import "./TestContracts/WstETHTokenMock.sol";
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
        vm.expectRevert(abi.encodeWithSelector(NewICRLowerThanMCR.selector, MathUtils._100_PERCENT));
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

        uint256 positionCollateralBefore = positionManager.raftCollateralToken().balanceOf(ALICE);
        uint256 collateralTopUpAmount = 1 ether;

        // Alice adds second collateral
        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), collateralTopUpAmount);
        positionManager.managePosition(collateralTopUpAmount, true, 0, false, ALICE, ALICE, 0);
        vm.stopPrank();

        uint256 positionCollateralAfter = positionManager.raftCollateralToken().balanceOf(ALICE);
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
        vm.expectRevert(abi.encodeWithSelector(PositionsListDoesNotContainNode.selector, CAROL));
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
        vm.expectRevert(PositionManagerOnlyOnePositionInSystem.selector);
        positionManager.managePosition(1 ether, true, 0, false, BOB, BOB, 0);
        vm.stopPrank();
    }
}
