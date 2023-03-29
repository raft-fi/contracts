// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import "../../contracts/SortedPositions.sol";

contract SortedPositionsTest is Test {
    IPositionManager public constant POSITION_MANAGER = IPositionManager(address(12345));

    address public constant ALICE = address(1);
    address public constant BOB = address(2);

    SortedPositions sortedPositions;

    function setUp() public {
        sortedPositions = new SortedPositions(10, POSITION_MANAGER);
    }

    // insert(): reverts when called by an account that is not Borrower Operations or Position Manager
    function testUnauthorizedInsert() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(CallerIsNotPositionManager.selector, ALICE));
        sortedPositions.insert(BOB, 150e18, BOB, BOB);
    }

    // remove(): reverts when called by an account that is not Position Manager
    function testUnauthorizedRemove() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(CallerIsNotPositionManager.selector, ALICE));
        sortedPositions.remove(BOB);
    }

    // reinsert(): reverts when called by an account that is neither BorrowerOps nor PositionManager
    function testUnauthorizedReinsert() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(CallerIsNotPositionManager.selector, ALICE));
        sortedPositions.reInsert(BOB, 150e18, BOB, BOB);
    }
}
