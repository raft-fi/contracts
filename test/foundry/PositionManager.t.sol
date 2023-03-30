// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../../contracts/PositionManager.sol";

contract PositionManagerTest is Test {
    IPriceFeed public constant PRICE_FEED = IPriceFeed(address(12345));
    IERC20 public constant COLLATERAL_TOKEN = IERC20(address(23456));
    uint256 public constant POSITIONS_SIZE = 10;

    address public constant USER = address(1);

    IPositionManager public positionManager;

    function setUp() public {
        positionManager = new PositionManager(PRICE_FEED, COLLATERAL_TOKEN, POSITIONS_SIZE);
    }

    function testSetBorrowingSpread() public {
        positionManager.setBorrowingSpread(100);
        assertEq(positionManager.borrowingSpread(), 100);
    }

    function testUnauthorizedSetBorrowingSpread() public {
        vm.prank(USER);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        positionManager.setBorrowingSpread(100);
    }

    function testOutOfBoundsSetBorrowingSpread() public {
        uint256 maxBorrowingSpread = positionManager.MAX_BORROWING_SPREAD();
        vm.expectRevert(BorrowingSpreadExceedsMaximum.selector);
        positionManager.setBorrowingSpread(maxBorrowingSpread + 1);
    }
}
