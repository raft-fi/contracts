// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { AggregatorV3Interface, IChainlinkPriceOracle } from "./Interfaces/IChainlinkPriceOracle.sol";
import { BasePriceOracle } from "./BasePriceOracle.sol";

contract ChainlinkPriceOracle is BasePriceOracle, IChainlinkPriceOracle {
    // --- Types ---

    using Fixed256x18 for uint256;

    // --- Constants & immutables ---

    AggregatorV3Interface public immutable override priceAggregator;

    uint256 public immutable override DEVIATION;

    uint256 public immutable override MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND;

    // --- Constructor ---

    constructor(
        AggregatorV3Interface _priceAggregatorAddress,
        uint256 _deviation,
        uint256 timeout_,
        uint256 targetDigits_,
        uint256 maxPriceDeviationFromPreviousRound_
    )
        BasePriceOracle(timeout_, targetDigits_)
    {
        if (address(_priceAggregatorAddress) == address(0)) {
            revert InvalidPriceAggregatorAddress();
        }
        if (_deviation >= 1e18) {
            revert InvalidDeviation();
        }
        priceAggregator = _priceAggregatorAddress;
        DEVIATION = _deviation;
        MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND = maxPriceDeviationFromPreviousRound_;
    }

    // --- Functions ---

    function getPriceOracleResponse() external override returns (PriceOracleResponse memory) {
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
                _formatPrice(uint256(chainlinkResponse.answer), chainlinkResponse.decimals)
            )
        );
    }

    function getPriceOracleResponseStatus() external view override returns (bool, bool) {
        ChainlinkResponse memory chainlinkResponse = _getCurrentChainlinkResponse();
        ChainlinkResponse memory prevChainlinkResponse =
            _getPrevChainlinkResponse(chainlinkResponse.roundId, chainlinkResponse.decimals);

        if (
            _chainlinkIsBroken(chainlinkResponse, prevChainlinkResponse)
                || _oracleIsFrozen(chainlinkResponse.timestamp)
        ) {
            return (true, false);
        }
        return (false, _chainlinkPriceChangeAboveMax(chainlinkResponse, prevChainlinkResponse));
    }

    function _getCurrentChainlinkResponse() internal view returns (ChainlinkResponse memory chainlinkResponse) {
        // First, try to get current decimal precision:
        try priceAggregator.decimals() returns (uint8 decimals) {
            // If call to Chainlink succeeds, record the current decimal precision
            chainlinkResponse.decimals = decimals;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return chainlinkResponse;
        }

        // Secondly, try to get latest price data:
        try priceAggregator.latestRoundData() returns (
            uint80 roundId, int256 answer, uint256, /* startedAt */ uint256 timestamp, uint80 answeredInRound
        ) {
            // If call to Chainlink succeeds, return the response and success = true
            chainlinkResponse.roundId = roundId;
            chainlinkResponse.answer = answer;
            chainlinkResponse.timestamp = timestamp;
            chainlinkResponse.answeredInRound = answeredInRound;
            chainlinkResponse.success = true;
            return chainlinkResponse;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return chainlinkResponse;
        }
    }

    function _getPrevChainlinkResponse(
        uint80 currentRoundID,
        uint8 currentDecimals
    )
        internal
        view
        returns (ChainlinkResponse memory prevChainlinkResponse)
    {
        /*
        * NOTE: Chainlink only offers a current decimals() value - there is no way to obtain the decimal precision used
        * in a previous round.  We assume the decimals used in the previous round are the same as the current round.
        */

        if (currentRoundID == 0) {
            return prevChainlinkResponse;
        }

        // Try to get the price data from the previous round:
        try priceAggregator.getRoundData(currentRoundID - 1) returns (
            uint80 roundId, int256 answer, uint256, /* startedAt */ uint256 timestamp, uint80 answeredInRound
        ) {
            // If call to Chainlink succeeds, return the response and success = true
            prevChainlinkResponse.roundId = roundId;
            prevChainlinkResponse.answer = answer;
            prevChainlinkResponse.timestamp = timestamp;
            prevChainlinkResponse.decimals = currentDecimals;
            prevChainlinkResponse.answeredInRound = answeredInRound;
            prevChainlinkResponse.success = true;
            return prevChainlinkResponse;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return prevChainlinkResponse;
        }
    }

    /* Chainlink is considered broken if its current or previous round data is in any way bad. We check the previous
    * round for two reasons:
    *
    * 1) It is necessary data for the price deviation check in case 1.
    * 2) Chainlink is the PriceFeed's preferred primary oracle - having two consecutive valid round responses adds
    * peace of mind when using or returning to Chainlink.
    */
    function _chainlinkIsBroken(
        ChainlinkResponse memory currentResponse,
        ChainlinkResponse memory prevResponse
    )
        internal
        view
        returns (bool)
    {
        return _badChainlinkResponse(currentResponse) || _badChainlinkResponse(prevResponse)
            || currentResponse.timestamp <= prevResponse.timestamp;
    }

    function _badChainlinkResponse(ChainlinkResponse memory response) internal view returns (bool) {
        return !response.success || response.roundId == 0 || response.timestamp == 0 || response.answer <= 0
            || response.answeredInRound != response.roundId || response.timestamp > block.timestamp;
    }

    function _chainlinkPriceChangeAboveMax(
        ChainlinkResponse memory currentResponse,
        ChainlinkResponse memory prevResponse
    )
        internal
        view
        returns (bool)
    {
        // Not needed to be converted to WstETH price, as we are only checking for a percentage change.
        // Also, not needed to be converted by decimals, because aggregator decimals are the same for both responses.
        uint256 currentScaledPrice = uint256(currentResponse.answer);
        uint256 prevScaledPrice = uint256(prevResponse.answer);

        uint256 minPrice = Math.min(currentScaledPrice, prevScaledPrice);
        uint256 maxPrice = Math.max(currentScaledPrice, prevScaledPrice);

        // Use the previous round price as the denominator
        uint256 percentDeviation = (maxPrice - minPrice).divDown(prevScaledPrice);

        // Return true if price has more than doubled, or more than halved.
        return percentDeviation > MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND;
    }
}
