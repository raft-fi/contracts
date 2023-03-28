// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import "../../contracts/SortedTroves.sol";

contract SortedTrovesTest is Test {
    ITroveManager public constant POSITIONS_MANAGER = ITroveManager(address(12345));
    IBorrowerOperations public constant BORROWER_OPERATIONS = IBorrowerOperations(address(34567));

    address public constant ALICE = address(1);
    address public constant BOB = address(2);

    SortedTroves sortedTroves;

    function setUp() public {
        sortedTroves = new SortedTroves();
        sortedTroves.setParams(10, POSITIONS_MANAGER, BORROWER_OPERATIONS);
    }

    // insert(): reverts when called by an account that is not Borrower Operations or Trove Manager
    function testUnauthorizedInsert() public {
        vm.prank(ALICE);
        vm.expectRevert(SortedTrovesInvalidCaller.selector);
        sortedTroves.insert(BOB, 150e18, BOB, BOB);
    }

    // remove(): reverts when called by an account that is not Trove Manager
    function testUnauthorizedRemove() public {
        vm.prank(ALICE);
        vm.expectRevert(CallerIsNotTroveManager.selector);
        sortedTroves.remove(BOB);
    }

    // reinsert(): reverts when called by an account that is neither BorrowerOps nor TroveManager
    function testUnauthorizedReinsert() public {
        vm.prank(ALICE);
        vm.expectRevert(SortedTrovesInvalidCaller.selector);
        sortedTroves.reInsert(BOB, 150e18, BOB, BOB);
    }
}
