// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import "../../contracts/ActivePool.sol";
import "../TestContracts/WstETHTokenMock.sol";

contract ActivePoolTest is Test {
    ITroveManager public constant POSITIONS_MANAGER = ITroveManager(address(12345));
    IDefaultPool public constant DEFAULT_POOL = IDefaultPool(address(56789));

    address public constant USER = address(1);

    IActivePool public activePool;
    WstETHTokenMock public collateralToken;

    function setUp() public {
        collateralToken = new WstETHTokenMock();

        activePool = new ActivePool(collateralToken);
        activePool.setAddresses(POSITIONS_MANAGER, DEFAULT_POOL);
    }

    // withdrawCollateral(): reverts when called by an account that is not Borrower Operations nor Trove Manager
    function testUnauthorizedSendETH() public {
        vm.prank(USER);
        vm.expectRevert(CallerIsNotTroveManager.selector);
        activePool.withdrawCollateral(USER, 100);
    }

    // increaseRDebt(): increases the R debt by the specified amount
    function testSuccessfulIncreaseRDebt() public {
        vm.prank(address(POSITIONS_MANAGER));
        activePool.increaseRDebt(100);
        assertEq(activePool.rDebt(), 100);
    }

    // increaseRDebt(): reverts when called by an account that is not Borrower Operations nor Trove Manager
    function testUnauthorizedIncreaseRDebt() public {
        vm.prank(USER);
        vm.expectRevert(CallerIsNotTroveManager.selector);
        activePool.increaseRDebt(100);
    }

    // decreaseRDebt(): decreases the R debt by the specified amount
    function testSuccessfulDecreaseRDebt() public {
        vm.prank(address(POSITIONS_MANAGER));
        activePool.increaseRDebt(100);
        assertEq(activePool.rDebt(), 100);

        vm.prank(address(POSITIONS_MANAGER));
        activePool.decreaseRDebt(100);
        assertEq(activePool.rDebt(), 0);
    }

    // decreaseRDebt(): reverts when called by an account that is not Borrower Operations nor Trove Manager
    function testUnauthorizedDecreaseRDebt() public {
        vm.prank(USER);
        vm.expectRevert(CallerIsNotTroveManager.selector);
        activePool.decreaseRDebt(100);
    }

    // depositCollateral(): reverts when called by an account that is not Borrower Operations nor Trove Manager
    function testUnauthorizedDepositCollateral() public {
        vm.startPrank(USER);
        collateralToken.approve(address(activePool), 100);
        vm.expectRevert(CallerIsNotTroveManager.selector);
        activePool.depositCollateral(USER, 100);
        vm.stopPrank();
    }

    // withdrawCollateral(): decreases the recorded ETH balance by the correct amount
    function testSuccessfulWithdrawCollateral() public {
        assertEq(collateralToken.balanceOf(address(activePool)), 0);

        // Start pool with 2 wstETH
        vm.startPrank(USER);
        collateralToken.mint(USER, 2e18);
        collateralToken.approve(address(activePool), 2e18);
        vm.stopPrank();
        vm.prank(address(POSITIONS_MANAGER));
        activePool.depositCollateral(USER, 2e18);

        uint256 activePoolBalanceBefore = collateralToken.balanceOf(address(activePool));
        uint256 userBalanceBefore = collateralToken.balanceOf(address(USER));

        assertEq(activePoolBalanceBefore, 2e18);

        // Send 1 wstETH from pool to user
        vm.startPrank(address(POSITIONS_MANAGER));
        activePool.withdrawCollateral(USER, 1e18);

        uint256 activePoolBalanceAfter = collateralToken.balanceOf(address(activePool));
        uint256 userBalanceAfter = collateralToken.balanceOf(address(USER));

        assertEq(userBalanceAfter - userBalanceBefore, 1e18);
        assertEq(activePoolBalanceBefore - activePoolBalanceAfter, 1e18);
    }
}
