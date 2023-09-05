// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { IWhitelistAddress } from "../contracts/Interfaces/IWhitelistAddress.sol";
import { WhitelistAddressMock } from "./mocks/WhitelistAddressMock.sol";

contract WhitelistAddress is Test {
    address public account = address(1234);
    address public account2 = address(12_345);

    IWhitelistAddress public whitelistAddress;

    function setUp() public {
        vm.startPrank(account);
        whitelistAddress = IWhitelistAddress(address(new WhitelistAddressMock()));
        vm.stopPrank();
    }

    function testAddWhitelistAddress() public {
        vm.startPrank(account);
        whitelistAddress.whitelistAddress(account2, true);
        assert(whitelistAddress.isWhitelisted(account2));
        vm.stopPrank();
    }

    function testCannotAddWhitelistAddress() public {
        vm.startPrank(account2);
        vm.expectRevert("Ownable: caller is not the owner");
        whitelistAddress.whitelistAddress(account2, true);
        vm.stopPrank();

        vm.startPrank(account);
        vm.expectRevert(abi.encodeWithSelector(IWhitelistAddress.InvalidWhitelistAddress.selector));
        whitelistAddress.whitelistAddress(address(0), true);
        vm.stopPrank();
    }
}
