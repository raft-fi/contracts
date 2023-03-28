// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import "../../contracts/ActivePool.sol";
import "../TestContracts/WstETHTokenMock.sol";

contract ActivePoolTest is Test {
    ITroveManager public constant POSITIONS_MANAGER = ITroveManager(address(12345));
    IBorrowerOperations public constant BORROWER_OPERATIONS = IBorrowerOperations(address(34567));
    IDefaultPool public constant DEFAULT_POOL = IDefaultPool(address(56789));

    address public constant USER = address(1);

    IActivePool public activePool;
    IERC20 public collateralToken;

    function setUp() public {
        collateralToken = new WstETHTokenMock();

        activePool = new ActivePool(collateralToken);
        activePool.setAddresses(BORROWER_OPERATIONS, POSITIONS_MANAGER, DEFAULT_POOL);
    }

    // sendETH(): reverts when called by an account that is not Borrower Operations nor Trove Manager
    function testUnauthorizedSendETH() public {
        vm.prank(USER);
        vm.expectRevert(ActivePoolInvalidCaller.selector);
        activePool.sendETH(USER, 100);
    }

    // increaseRDebt(): reverts when called by an account that is not Borrower Operations nor Trove Manager
    function testUnauthorizedIncreaseRDebt() public {
        vm.prank(USER);
        vm.expectRevert(ActivePoolInvalidCaller.selector);
        activePool.increaseRDebt(100);
    }

    // decreaseRDebt(): reverts when called by an account that is not Borrower Operations nor Trove Manager
    function testUnauthorizedDecreaseRDebt() public {
        vm.prank(USER);
        vm.expectRevert(ActivePoolInvalidCaller.selector);
        activePool.decreaseRDebt(100);
    }

    // depositCollateral(): reverts when called by an account that is not Borrower Operations nor Trove Manager
    function testUnauthorizedDepositCollateral() public {
        vm.startPrank(USER);
        collateralToken.approve(address(activePool), 100);
        vm.expectRevert(ActivePoolInvalidCaller.selector);
        activePool.depositCollateral(USER, 100);
        vm.stopPrank();
    }
}
