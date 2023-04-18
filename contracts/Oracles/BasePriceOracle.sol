// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Fixed256x18} from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import {MathUtils} from "../Dependencies/MathUtils.sol";
import {IWstETH} from "../Dependencies/IWstETH.sol";
import {IPriceOracle} from "./Interfaces/IPriceOracle.sol";

abstract contract BasePriceOracle is IPriceOracle {
    using Fixed256x18 for uint256;

    IWstETH public immutable override wstETH;

    uint256 public constant override TIMEOUT = 3 hours;

    uint256 public constant override TARGET_DIGITS = 18;

    constructor(IWstETH _wstETH) {
        if (address(_wstETH) == address(0)) {
            revert InvalidWstETHAddress();
        }
        wstETH = IWstETH(_wstETH);
    }

    function _oracleIsFrozen(uint256 responseTimestamp) internal view returns (bool) {
        return (block.timestamp - responseTimestamp) > TIMEOUT;
    }

    function _convertIntoWstETHPrice(uint256 _price, uint256 _answerDigits) internal view returns (uint256) {
        return _scalePriceByDigits(_price, _answerDigits).mulDown(wstETH.stEthPerToken());
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
