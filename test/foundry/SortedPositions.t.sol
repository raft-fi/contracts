// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import "../../contracts/SortedPositions.sol";

contract SortedPositionsTest is Test {
    IPositionManager public constant POSITIONS_MANAGER = IPositionManager(address(12345));

    address public constant ALICE = address(1);
    address public constant BOB = address(2);

    SortedPositions sortedPositions;

    function setUp() public {
        sortedPositions = new SortedPositions();
        sortedPositions.setParams(10, POSITIONS_MANAGER);
    }

    // insert(): reverts when called by an account that is not Borrower Operations or Position Manager
    function testUnauthorizedInsert() public {
        vm.prank(ALICE);
        vm.expectRevert(CallerIsNotPositionManager.selector);
        sortedPositions.insert(BOB, 150e18, BOB, BOB);
    }

    // remove(): reverts when called by an account that is not Position Manager
    function testUnauthorizedRemove() public {
        vm.prank(ALICE);
        vm.expectRevert(CallerIsNotPositionManager.selector);
        sortedPositions.remove(BOB);
    }

    // reinsert(): reverts when called by an account that is neither BorrowerOps nor PositionManager
    function testUnauthorizedReinsert() public {
        vm.prank(ALICE);
        vm.expectRevert(CallerIsNotPositionManager.selector);
        sortedPositions.reInsert(BOB, 150e18, BOB, BOB);
    }
}
