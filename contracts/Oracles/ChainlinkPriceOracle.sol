// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "../Dependencies/MathUtils.sol";
import "./Interfaces/IChainlinkPriceOracle.sol";
import "./BasePriceOracle.sol";

contract ChainlinkPriceOracle is IChainlinkPriceOracle, BasePriceOracle {
    
    AggregatorV3Interface public immutable override priceAggregator;

    uint256 constant public override MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND =  5e17; // 50%

    constructor(AggregatorV3Interface _priceAggregatorAddress) {
        if (address(_priceAggregatorAddress) == address(0)) {
            revert InvalidPriceAggregatorAddress();
        }
        priceAggregator = _priceAggregatorAddress;
    }


    function getPriceOracleResponse() external view override returns(PriceOracleResponse memory) {
        ChainlinkResponse memory _chainlinkResponse = _getCurrentChainlinkResponse();
        ChainlinkResponse memory _prevChainlinkResponse = _getPrevChainlinkResponse(_chainlinkResponse.roundId, _chainlinkResponse.decimals);

        if (_chainlinkIsBroken(_chainlinkResponse, _prevChainlinkResponse) || _oracleIsFrozen(_chainlinkResponse.timestamp)) {
            return(PriceOracleResponse(true, false, 0));
        }
        return (PriceOracleResponse(
            false,
            _chainlinkPriceChangeAboveMax(_chainlinkResponse, _prevChainlinkResponse),
            _scalePriceByDigits(uint256(_chainlinkResponse.answer), _chainlinkResponse.decimals)
        ));
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
        try priceAggregator.latestRoundData() returns
        (
            uint80 roundId,
            int256 answer,
            uint256 /* startedAt */,
            uint256 timestamp,
            uint80 /* answeredInRound */
        )
        {
            // If call to Chainlink succeeds, return the response and success = true
            chainlinkResponse.roundId = roundId;
            chainlinkResponse.answer = answer;
            chainlinkResponse.timestamp = timestamp;
            chainlinkResponse.success = true;
            return chainlinkResponse;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return chainlinkResponse;
        }
    }

    function _getPrevChainlinkResponse(uint80 _currentRoundId, uint8 _currentDecimals) internal view returns (ChainlinkResponse memory prevChainlinkResponse) {
        /*
        * NOTE: Chainlink only offers a current decimals() value - there is no way to obtain the decimal precision used in a
        * previous round.  We assume the decimals used in the previous round are the same as the current round.
        */

        if (_currentRoundId == 0) {
            return prevChainlinkResponse;
        }

        // Try to get the price data from the previous round:
        try priceAggregator.getRoundData(_currentRoundId - 1) returns
        (
            uint80 roundId,
            int256 answer,
            uint256 /* startedAt */,
            uint256 timestamp,
            uint80 /* answeredInRound */
        )
        {
            // If call to Chainlink succeeds, return the response and success = true
            prevChainlinkResponse.roundId = roundId;
            prevChainlinkResponse.answer = answer;
            prevChainlinkResponse.timestamp = timestamp;
            prevChainlinkResponse.decimals = _currentDecimals;
            prevChainlinkResponse.success = true;
            return prevChainlinkResponse;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return prevChainlinkResponse;
        }
    }

    /* Chainlink is considered broken if its current or previous round data is in any way bad. We check the previous round
    * for two reasons:
    *
    * 1) It is necessary data for the price deviation check in case 1,
    * and
    * 2) Chainlink is the PriceFeed's preferred primary oracle - having two consecutive valid round responses adds
    * peace of mind when using or returning to Chainlink.
    */
    function _chainlinkIsBroken(ChainlinkResponse memory _currentResponse, ChainlinkResponse memory _prevResponse) internal view returns (bool) {
        return _badChainlinkResponse(_currentResponse) || _badChainlinkResponse(_prevResponse);
    }

    function _badChainlinkResponse(ChainlinkResponse memory _response) internal view returns (bool) {
        return !_response.success || _response.roundId == 0 || _response.timestamp == 0 || _response.timestamp > block.timestamp || _response.answer <= 0;
    }

    function _chainlinkPriceChangeAboveMax(ChainlinkResponse memory _currentResponse, ChainlinkResponse memory _prevResponse) internal pure returns (bool) {
        uint256 currentScaledPrice = _scalePriceByDigits(uint256(_currentResponse.answer), _currentResponse.decimals);
        uint256 prevScaledPrice = _scalePriceByDigits(uint256(_prevResponse.answer), _prevResponse.decimals);

        uint256 minPrice = Math.min(currentScaledPrice, prevScaledPrice);
        uint256 maxPrice = Math.max(currentScaledPrice, prevScaledPrice);

        /*
        * Use the larger price as the denominator:
        * - If price decreased, the percentage deviation is in relation to the the previous price.
        * - If price increased, the percentage deviation is in relation to the current price.
        */
        uint256 percentDeviation = (maxPrice - minPrice) * MathUtils.DECIMAL_PRECISION / maxPrice;

        // Return true if price has more than doubled, or more than halved.
        return percentDeviation > MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND;
    }
}
