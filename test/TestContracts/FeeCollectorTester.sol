// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {FeeCollector} from "../../contracts/FeeCollector.sol";

contract FeeCollectorTester is FeeCollector {
    // solhint-disable-next-line no-empty-blocks
    constructor(address feeRecipient) FeeCollector(feeRecipient) {}
}
