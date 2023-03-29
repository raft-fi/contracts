// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../../contracts/FeeCollector.sol";

contract FeeCollectorTest is Test {
    IFeeCollector public feeable;

    address public constant FEE_RECIPIENT1 = address(1);
    address public constant FEE_RECIPIENT2 = address(2);

    function setUp() public {
        feeable = new FeeCollector(FEE_RECIPIENT1);
    }

    function testSetFeeRecipient() public {
        assertEq(feeable.feeRecipient(), FEE_RECIPIENT1);

        feeable.setFeeRecipient(FEE_RECIPIENT2);
        assertEq(feeable.feeRecipient(), FEE_RECIPIENT2);
    }

    function testUnauthorizedSetFeeRecipient() public {
        vm.prank(FEE_RECIPIENT1);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        feeable.setFeeRecipient(FEE_RECIPIENT1);
    }

    function testInvalidSetFeeRecipient() public {
        vm.expectRevert(InvalidFeeRecipient.selector);
        feeable.setFeeRecipient(address(0));
    }
}
