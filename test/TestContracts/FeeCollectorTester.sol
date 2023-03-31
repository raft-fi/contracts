// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../contracts/FeeCollector.sol";

contract FeeCollectorTester is FeeCollector {
    constructor(address feeRecipient) FeeCollector(feeRecipient) { }
}