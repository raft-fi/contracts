// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { MathUtils } from "../Dependencies/MathUtils.sol";
import { IWstETH } from "../Dependencies/IWstETH.sol";
import { IPriceOracle } from "./Interfaces/IPriceOracle.sol";

abstract contract BasePriceOracle is IPriceOracle {
    // --- Types ---

    using Fixed256x18 for uint256;

    // --- Variables ---

    IWstETH public immutable override wstETH;

    uint256 public constant override TIMEOUT = 3 hours;

    uint256 public constant override TARGET_DIGITS = 18;

    // --- Constructor ---

    constructor(IWstETH wstETH_) {
        if (address(wstETH_) == address(0)) {
            revert InvalidWstETHAddress();
        }
        wstETH = IWstETH(wstETH_);
    }

    // --- Functions ---

    function _oracleIsFrozen(uint256 responseTimestamp) internal view returns (bool) {
        return (block.timestamp - responseTimestamp) > TIMEOUT;
    }

    function _convertIntoWstETHPrice(uint256 price, uint256 answerDigits) internal view returns (uint256) {
        return _scalePriceByDigits(price, answerDigits).mulDown(wstETH.stEthPerToken());
    }

    function _scalePriceByDigits(uint256 price, uint256 answerDigits) internal pure returns (uint256) {
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
