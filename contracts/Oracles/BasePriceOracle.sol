// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IPriceOracle } from "./Interfaces/IPriceOracle.sol";

abstract contract BasePriceOracle is IPriceOracle {
    // --- Immutables ---

    uint256 public immutable override timeout;

    uint256 public immutable override targetDigits;

    // --- Constructor ---

    constructor(uint256 timeout_, uint256 targetDigits_) {
        timeout = timeout_;
        targetDigits = targetDigits_;
    }

    // --- Functions ---

    function _oracleIsFrozen(uint256 responseTimestamp) internal view returns (bool) {
        return (block.timestamp - responseTimestamp) > timeout;
    }

    function _formatPrice(uint256 price, uint256 answerDigits) internal virtual returns (uint256) {
        /*
        * Convert the price returned by the oracle to an 18-digit decimal for use by Raft.
        */
        if (answerDigits > targetDigits) {
            // Scale the returned price value down to Raft's target precision
            return price / (10 ** (answerDigits - targetDigits));
        }
        if (answerDigits < targetDigits) {
            // Scale the returned price value up to Raft's target precision
            return price * (10 ** (targetDigits - answerDigits));
        }
        return price;
    }
}
