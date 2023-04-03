// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../Dependencies/AggregatorV3Interface.sol";
import "./IPriceOracle.sol";

error InvalidPriceAggregatorAddress();

struct ChainlinkResponse {
    uint80 roundId;
    int256 answer;
    uint256 timestamp;
    bool success;
    uint8 decimals;
}

interface IChainlinkPriceOracle is IPriceOracle {
    /// @dev Mainnet Chainlink aggregator.
    function priceAggregator() external returns(AggregatorV3Interface);

    /// @dev Maximum deviation allowed between two consecutive Chainlink oracle prices. 18-digit precision.
    function MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND() external returns(uint256);
}
