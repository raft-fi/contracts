// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";

import { RaftToken } from "../contracts/Token/RaftToken.sol";
import { IRaftToken } from "../contracts/Token/IRaftToken.sol";

contract RaftTokenTest is Test {
    RaftToken public raftToken;

    function setUp() public {
        raftToken = new RaftToken();
    }

    function testMint() public {
        vm.prank(address(1234));
        vm.expectRevert("Ownable: caller is not the owner");
        raftToken.mint(address(1), 1);

        vm.expectRevert(IRaftToken.MintingToZeroAddressNotAllowed.selector);
        raftToken.mint(address(0), 1);

        vm.expectRevert(IRaftToken.MintingNotAllowedYet.selector);
        raftToken.mint(address(1234), 1);

        vm.warp(raftToken.mintingAllowedAfter());
        vm.expectRevert(
            abi.encodeWithSelector(IRaftToken.MintAmountIsGreaterThanCap.selector, 250_000_001e18, 250_000_000e18)
        );
        raftToken.mint(address(1234), 250_000_001e18);

        raftToken.mint(address(1234), 250_000_000e18);
        assertEq(raftToken.balanceOf(address(1234)), 250_000_000e18);

        vm.expectRevert(IRaftToken.NotEnoughTimeBetweenMints.selector);
        raftToken.mint(address(1234), 1);
    }

    function testBurn() public {
        raftToken.transfer(address(1234), 10e18);

        vm.prank(address(1234));
        raftToken.burn(1e18);

        assertEq(raftToken.balanceOf(address(1234)), 9e18);
    }

    function testRescue() public {
        vm.prank(address(1234));
        vm.expectRevert("Ownable: caller is not the owner");
        raftToken.rescueTokens(raftToken, address(1234));

        raftToken.transfer(address(raftToken), 10e18);
        assertEq(raftToken.balanceOf(address(raftToken)), 10e18);

        raftToken.rescueTokens(raftToken, address(1234));

        assertEq(raftToken.balanceOf(address(raftToken)), 0);
        assertEq(raftToken.balanceOf(address(1234)), 10e18);
    }

    function testRename() public {
        vm.prank(address(1234));
        vm.expectRevert("Ownable: caller is not the owner");
        raftToken.renameToken("RaFt", "RFT");

        vm.expectRevert(IRaftToken.NewTokenNameIsEmpty.selector);
        raftToken.renameToken("", "");

        vm.expectRevert(IRaftToken.NewTokenSymbolIsEmpty.selector);
        raftToken.renameToken("RaFt", "");

        raftToken.renameToken("RaFt", "RFT");

        assertEq(raftToken.name(), "RaFt");
        assertEq(raftToken.symbol(), "RFT");
    }
}
