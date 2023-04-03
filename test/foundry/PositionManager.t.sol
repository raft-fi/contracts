// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../../contracts/PositionManager.sol";
import "./utils/TestSetup.t.sol";

contract PositionManagerTest is TestSetup {
    uint256 public constant POSITIONS_SIZE = 10;
    uint256 public constant LIQUIDATION_PROTOCOL_FEE = 0;

    IPositionManager public positionManager;

    function setUp() public {
        positionManager = new PositionManager(PRICE_FEED, COLLATERAL_TOKEN, POSITIONS_SIZE, LIQUIDATION_PROTOCOL_FEE);
    }

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
}
