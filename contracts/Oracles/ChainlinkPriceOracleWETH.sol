// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { AggregatorV3Interface, BaseChainlinkPriceOracle } from "./BaseChainlinkPriceOracle.sol";
import { BasePriceOracle } from "./BasePriceOracle.sol";

contract ChainlinkPriceOracleWETH is BaseChainlinkPriceOracle, BasePriceOracle {
    // --- Constants ---

    uint256 public constant override DEVIATION = 5e15; // 0.5%

    // --- Constructor ---

    // solhint-disable-next-line no-empty-blocks
    constructor(AggregatorV3Interface _priceAggregatorAddress) BaseChainlinkPriceOracle(_priceAggregatorAddress) { }

    // --- Functions ---

    function getPriceOracleResponse() external view override returns (PriceOracleResponse memory) {
        ChainlinkResponse memory chainlinkResponse = _getCurrentChainlinkResponse();
        ChainlinkResponse memory prevChainlinkResponse =
            _getPrevChainlinkResponse(chainlinkResponse.roundId, chainlinkResponse.decimals);

        if (
            _chainlinkIsBroken(chainlinkResponse, prevChainlinkResponse)
                || _oracleIsFrozen(chainlinkResponse.timestamp)
        ) {
            return (PriceOracleResponse(true, false, 0));
        }
        return (
            PriceOracleResponse(
                false,
                _chainlinkPriceChangeAboveMax(chainlinkResponse, prevChainlinkResponse),
                _scalePriceByDigits(uint256(chainlinkResponse.answer), chainlinkResponse.decimals)
            )
        );
    }
}
