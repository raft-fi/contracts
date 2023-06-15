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
                _convertIntoWstETHPrice(uint256(chainlinkResponse.answer), chainlinkResponse.decimals)
            )
        );
    }
}
