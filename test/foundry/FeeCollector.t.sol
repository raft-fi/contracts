// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../TestContracts/FeeCollectorTester.sol";

contract FeeCollectorTest is Test {
    IFeeCollector public feeCollector;

    address public constant FEE_RECIPIENT1 = address(1);
    address public constant FEE_RECIPIENT2 = address(2);

    function setUp() public {
        feeCollector = new FeeCollectorTester(FEE_RECIPIENT1);
    }

    function testSetFeeRecipient() public {
        assertEq(feeCollector.feeRecipient(), FEE_RECIPIENT1);

        feeCollector.setFeeRecipient(FEE_RECIPIENT2);
        assertEq(feeCollector.feeRecipient(), FEE_RECIPIENT2);
    }

    function testUnauthorizedSetFeeRecipient() public {
        vm.prank(FEE_RECIPIENT1);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        feeCollector.setFeeRecipient(FEE_RECIPIENT1);
    }

    function testInvalidSetFeeRecipient() public {
        vm.expectRevert(InvalidFeeRecipient.selector);
        feeCollector.setFeeRecipient(address(0));
    }
}
