// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { IWstETH } from "../Dependencies/IWstETH.sol";
import { IPriceOracleWstETH } from "./Interfaces/IPriceOracleWstETH.sol";
import { BasePriceOracle } from "./BasePriceOracle.sol";

abstract contract BasePriceOracleWstETH is BasePriceOracle, IPriceOracleWstETH {
    // --- Types ---

    using Fixed256x18 for uint256;

    // --- Variables ---

    IWstETH public immutable override wstETH;

    // --- Constructor ---

    constructor(IWstETH wstETH_) {
        if (address(wstETH_) == address(0)) {
            revert InvalidWstETHAddress();
        }
        wstETH = IWstETH(wstETH_);
    }

    // --- Functions ---

    function _convertIntoWstETHPrice(uint256 price, uint256 answerDigits) internal view returns (uint256) {
        return _scalePriceByDigits(price, answerDigits).mulDown(wstETH.stEthPerToken());
    }
}
