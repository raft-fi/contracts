// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IPriceOracle } from "./Interfaces/IPriceOracle.sol";

abstract contract BasePriceOracle is IPriceOracle {
    // --- Variables ---

    uint256 public constant override TIMEOUT = 3 hours;

    uint256 public constant override TARGET_DIGITS = 18;

    // --- Functions ---

    function _oracleIsFrozen(uint256 responseTimestamp) internal view returns (bool) {
        return (block.timestamp - responseTimestamp) > TIMEOUT;
    }

    function _formatPrice(uint256 price, uint256 answerDigits) internal view virtual returns (uint256) {
        /*
        * Convert the price returned by the oracle to an 18-digit decimal for use by Raft.
        */
        if (answerDigits > TARGET_DIGITS) {
            // Scale the returned price value down to Raft's target precision
            return price / (10 ** (answerDigits - TARGET_DIGITS));
        }
        if (answerDigits < TARGET_DIGITS) {
            // Scale the returned price value up to Raft's target precision
            return price * (10 ** (TARGET_DIGITS - answerDigits));
        }
        return price;
    }
}
