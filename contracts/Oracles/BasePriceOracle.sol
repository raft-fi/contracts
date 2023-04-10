// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IPriceOracle } from "./Interfaces/IPriceOracle.sol";

abstract contract BasePriceOracle is IPriceOracle {
    uint256 public constant override TIMEOUT = 4 hours;

    uint256 public constant override TARGET_DIGITS = 18;

    function _oracleIsFrozen(uint256 responseTimestamp) internal view returns (bool) {
        return (block.timestamp - responseTimestamp) > TIMEOUT;
    }

    function _scalePriceByDigits(uint256 _price, uint256 _answerDigits) internal pure returns (uint256) {
        /*
        * Convert the price returned by the oracle to an 18-digit decimal for use by Raft.
        */
        if (_answerDigits > TARGET_DIGITS) {
            // Scale the returned price value down to Raft's target precision
            return _price / (10 ** (_answerDigits - TARGET_DIGITS));
        }
        if (_answerDigits < TARGET_DIGITS) {
            // Scale the returned price value up to Raft's target precision
            return _price * (10 ** (TARGET_DIGITS - _answerDigits));
        }
        return _price;
    }
}
