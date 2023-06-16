// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { AggregatorV3Interface, BaseChainlinkPriceOracle } from "./BaseChainlinkPriceOracle.sol";

contract ChainlinkPriceOracleWETH is BaseChainlinkPriceOracle {
    // --- Constants ---

    uint256 public constant override DEVIATION = 5e15; // 0.5%

    // --- Constructor ---

    // solhint-disable-next-line no-empty-blocks
    constructor(AggregatorV3Interface _priceAggregatorAddress) BaseChainlinkPriceOracle(_priceAggregatorAddress) { }

    // --- Functions ---

    function _formatPrice(uint256 price, uint256 answerDigits) internal view override returns (uint256) {
        return _scalePriceByDigits(price, answerDigits);
    }
}
