// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { AggregatorV3Interface } from "@smartcontractkit/chainlink/interfaces/AggregatorV3Interface.sol";
import { IPriceOracle } from "./IPriceOracle.sol";

interface IChainlinkPriceOracle is IPriceOracle {
    // --- Types ---

    struct ChainlinkResponse {
        uint80 roundId;
        int256 answer;
        uint256 timestamp;
        bool success;
        uint8 decimals;
    }

    // --- Errors ---

    /// @dev Emitted when the price aggregator address is invalid.
    error InvalidPriceAggregatorAddress();

    // --- Functions ---

    /// @dev Mainnet Chainlink aggregator.
    function priceAggregator() external returns (AggregatorV3Interface);

    /// @dev Maximum deviation allowed between two consecutive Chainlink oracle prices. 18-digit precision.
    function MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND() external returns (uint256);
}
