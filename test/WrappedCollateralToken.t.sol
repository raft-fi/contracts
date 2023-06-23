// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { IPositionManagerDependent } from "../contracts/Interfaces/IPositionManagerDependent.sol";
import { IWrappedCollateralToken } from "../contracts/Interfaces/IWrappedCollateralToken.sol";
import { PositionManager } from "../contracts/PositionManager.sol";
import { SplitLiquidationCollateral } from "../contracts/SplitLiquidationCollateral.sol";
import { WrappedCollateralToken } from "../contracts/WrappedCollateralToken.sol";
import { PriceFeedTestnet } from "./mocks/PriceFeedTestnet.sol";
import { TokenMock } from "./mocks/TokenMock.sol";

contract WrappedCollateralTokenTest is Test {
    TokenMock public underlying;
    WrappedCollateralToken public wrapped;
    PositionManager public positionManager;
    address public account = address(1234);
    address public account2 = address(12_345);

    function setUp() public {
        vm.startPrank(account);
        underlying = new TokenMock();
        positionManager = new PositionManager();
        wrapped = new WrappedCollateralToken(
            underlying, "Wrapped Token Mock", "WRPTKMCK", type(uint256).max, type(uint256).max, address(positionManager)
        );

        PriceFeedTestnet priceFeed = new PriceFeedTestnet();
        priceFeed.setPrice(1e18);
        SplitLiquidationCollateral splitLiquidationCollateral = new SplitLiquidationCollateral();
        positionManager.addCollateralToken(wrapped, priceFeed, splitLiquidationCollateral);

        wrapped.whitelistAddress(account, true);
        vm.stopPrank();
    }

    function testDepositFor(
        uint256 maxBalance,
        uint256 cap,
        uint256 toDeposit,
        uint256 preSupply,
        uint256 preBalance
    )
        public
    {
        vm.startPrank(account);

        cap = bound(cap, 1e15, 1e45);
        toDeposit = bound(toDeposit, 1, cap);
        maxBalance = bound(maxBalance, 0, cap);
        preBalance = bound(preBalance, 0, maxBalance);
        preSupply = bound(preSupply, preBalance, cap);

        // set the wrapped token to a pre state
        underlying.mint(account, preSupply + toDeposit);
        underlying.approve(address(wrapped), preSupply + toDeposit);
        wrapped.depositFor(account, preBalance);
        // mint remider fo preSupply
        wrapped.depositFor(account2, preSupply - preBalance);

        wrapped.setCap(cap);
        wrapped.setMaxBalance(maxBalance);
        bool noRevert = true;

        if (preSupply + toDeposit > cap) {
            vm.expectRevert(IWrappedCollateralToken.ExceedsCap.selector);
            noRevert = false;
        } else if (preBalance + toDeposit > maxBalance) {
            vm.expectRevert(IWrappedCollateralToken.ExceedsMaxBalance.selector);
            noRevert = false;
        }
        wrapped.depositFor(account, toDeposit);
        if (noRevert) {
            assertEq(wrapped.balanceOf(account), preBalance + toDeposit);
            assertEq(wrapped.totalSupply(), preSupply + toDeposit);
            assertEq(underlying.balanceOf(address(wrapped)), preSupply + toDeposit);
        }

        vm.stopPrank();
    }

    function testCannotDepositFor() public {
        vm.startPrank(account2);

        vm.expectRevert(abi.encodeWithSelector(IWrappedCollateralToken.AddressIsNotWhitelisted.selector, account2));
        wrapped.depositFor(account2, 501e18);
        vm.stopPrank();
    }

    function testCannotTransfers() public {
        vm.startPrank(account);

        // set the wrapped token to a pre state
        underlying.mint(account, 1000e18);
        underlying.approve(address(wrapped), 1000e18);
        wrapped.depositFor(account, 1000e18);

        vm.expectRevert(abi.encodeWithSelector(IPositionManagerDependent.CallerIsNotPositionManager.selector, account));
        wrapped.transfer(account2, 501e18);
        vm.stopPrank();
    }

    function testAddWhitelistAddress() public {
        vm.startPrank(account);
        wrapped.whitelistAddress(account2, true);
        assert(wrapped.isWhitelisted(account2));
        vm.stopPrank();
    }

    function testCannotAddWhitelistAddress() public {
        vm.startPrank(account2);
        vm.expectRevert("Ownable: caller is not the owner");
        wrapped.whitelistAddress(account2, true);
        vm.stopPrank();

        vm.startPrank(account);
        vm.expectRevert(abi.encodeWithSelector(IWrappedCollateralToken.InvalidWhitelistAddress.selector));
        wrapped.whitelistAddress(address(0), true);
        vm.stopPrank();
    }

    function testRecoverCallableByOwnerOnly() public {
        vm.prank(account2);
        vm.expectRevert("Ownable: caller is not the owner");
        wrapped.recover(account2);
    }
}
