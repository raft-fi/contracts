// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IWstETH } from "../Dependencies/IWstETH.sol";
import { AggregatorV3Interface, BaseChainlinkPriceOracle } from "./BaseChainlinkPriceOracle.sol";
import { BasePriceOracleWstETH } from "./BasePriceOracleWstETH.sol";

contract ChainlinkPriceOracleWstETH is BaseChainlinkPriceOracle, BasePriceOracleWstETH {
    // --- Constants ---

    uint256 public constant override DEVIATION = 1e16; // 1%

    // --- Constructor ---

    constructor(
        AggregatorV3Interface _priceAggregatorAddress,
        IWstETH _wstETH
    )
        BaseChainlinkPriceOracle(_priceAggregatorAddress)
        BasePriceOracleWstETH(_wstETH)
    // solhint-disable-next-line no-empty-blocks
    { }

    // --- Functions ---

    function _formatPrice(uint256 price, uint256 answerDigits) internal view override returns (uint256) {
        return _convertIntoWstETHPrice(price, answerDigits);
    }
}
