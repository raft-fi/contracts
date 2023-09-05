// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { IWhitelistAddress } from "../contracts/Interfaces/IWhitelistAddress.sol";
import { RTokenL2 } from "../contracts/RTokenL2.sol";

contract RTokenL2Test is Test {
    RTokenL2 public rTokenL2;
    address public account = address(1234);
    address public account2 = address(12_345);

    function setUp() public {
        vm.startPrank(account);
        rTokenL2 = new RTokenL2("R on Base", "RBASE");
        rTokenL2.whitelistAddress(account, true);
        vm.stopPrank();
    }

    function testMint() public {
        vm.startPrank(account);

        uint256 preSupply = rTokenL2.totalSupply();
        uint256 preBalance = rTokenL2.balanceOf(account);

        uint256 toMint = 1000e18;
        rTokenL2.mint(account, toMint);

        assertEq(rTokenL2.totalSupply(), preSupply + toMint);
        assertEq(rTokenL2.balanceOf(account), preBalance + toMint);

        vm.stopPrank();
    }

    function testCannotMint() public {
        vm.startPrank(account2);

        vm.expectRevert(abi.encodeWithSelector(IWhitelistAddress.AddressIsNotWhitelisted.selector, account2));
        rTokenL2.mint(account2, 501e18);
        vm.stopPrank();
    }

    function testBurn() public {
        vm.startPrank(account);
        rTokenL2.mint(account, 1_000_000e18);

        uint256 preSupply = rTokenL2.totalSupply();
        uint256 preBalance = rTokenL2.balanceOf(account);

        uint256 toBurn = 1000e18;
        rTokenL2.burn(toBurn);

        assertEq(rTokenL2.totalSupply(), preSupply - toBurn);
        assertEq(rTokenL2.balanceOf(account), preBalance - toBurn);

        vm.stopPrank();
    }

    function testCannotBurn() public {
        vm.startPrank(account2);

        vm.expectRevert(abi.encodeWithSelector(IWhitelistAddress.AddressIsNotWhitelisted.selector, account2));
        rTokenL2.burn(501e18);
        vm.stopPrank();
    }
}
