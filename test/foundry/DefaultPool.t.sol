// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import "../../contracts/DefaultPool.sol";
import "../TestContracts/WstETHTokenMock.sol";

contract DefaultPoolTest is Test {
    ITroveManager public constant POSITIONS_MANAGER = ITroveManager(address(12345));

    address public constant USER = address(1);

    IDefaultPool public defaultPool;
    IERC20 public collateralToken;

    function setUp() public {
        collateralToken = new WstETHTokenMock();

        defaultPool = new DefaultPool(collateralToken);
        defaultPool.setAddresses(POSITIONS_MANAGER);
    }

    // withdrawCollateral(): reverts when called by an account that is not Trove Manager
    function testUnauthorizedSendETH() public {
        vm.prank(USER);
        vm.expectRevert(CallerIsNotTroveManager.selector);
        defaultPool.withdrawCollateral(USER, 100);
    }

    // increaseRDebt(): increases the R debt by the specified amount
    function testSuccessfulIncreaseRDebt() public {
        vm.prank(address(POSITIONS_MANAGER));
        defaultPool.increaseRDebt(100);
        assertEq(defaultPool.rDebt(), 100);
    }

    // increaseRDebt(): reverts when called by an account that is not Trove Manager
    function testUnauthorizedIncreaseRDebt() public {
        vm.prank(USER);
        vm.expectRevert(CallerIsNotTroveManager.selector);
        defaultPool.increaseRDebt(100);
    }

    // decreaseRDebt(): decreases the R debt by the specified amount
    function testSuccessfulDecreaseRDebt() public {
        vm.prank(address(POSITIONS_MANAGER));
        defaultPool.increaseRDebt(100);
        assertEq(defaultPool.rDebt(), 100);

        vm.prank(address(POSITIONS_MANAGER));
        defaultPool.decreaseRDebt(100);
        assertEq(defaultPool.rDebt(), 0);
    }

    // decreaseRDebt(): reverts when called by an account that is not Trove Manager
    function testUnauthorizedDecreaseRDebt() public {
        vm.prank(USER);
        vm.expectRevert(CallerIsNotTroveManager.selector);
        defaultPool.decreaseRDebt(100);
    }

    // depositCollateral(): reverts when called by an account that is not Trove Manager
    function testUnauthorizedDepositCollateral() public {
        vm.startPrank(USER);
        collateralToken.approve(address(defaultPool), 100);
        vm.expectRevert(CallerIsNotTroveManager.selector);
        defaultPool.depositCollateral(USER, 100);
        vm.stopPrank();
    }
}
