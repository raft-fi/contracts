// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../TestContracts/FeeCollectorTester.sol";
import "./utils/TestSetup.t.sol";

contract FeeCollectorTest is TestSetup {
    IFeeCollector public feeCollector;

    function setUp() public {
        feeCollector = new FeeCollectorTester(FEE_RECIPIENT);
    }

    function testSetFeeRecipient() public {
        assertEq(feeCollector.feeRecipient(), FEE_RECIPIENT);

        feeCollector.setFeeRecipient(NEW_FEE_RECIPIENT);
        assertEq(feeCollector.feeRecipient(), NEW_FEE_RECIPIENT);
    }

    function testUnauthorizedSetFeeRecipient() public {
        vm.prank(FEE_RECIPIENT);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        feeCollector.setFeeRecipient(FEE_RECIPIENT);
    }

    function testInvalidSetFeeRecipient() public {
        vm.expectRevert(InvalidFeeRecipient.selector);
        feeCollector.setFeeRecipient(address(0));
    }
}
