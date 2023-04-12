// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

struct PriceOracleResponse {
    bool isBrokenOrFrozen;
    bool priceChangeAboveMax;
    uint256 price;
}

interface IPriceOracle {
    /// @dev Maximum time period allowed since oracle latest round data timestamp, beyond which oracle is considered
    /// frozen.
    function TIMEOUT() external view returns (uint256);

    /// @dev Used to convert a price answer to an 18-digit precision uint.
    function TARGET_DIGITS() external view returns (uint256);

    /// @dev Return price oracle response which consists next information:
    ///         oracle is broken or frozen, the price change between two rounds is more than max, and the price.
    function getPriceOracleResponse() external view returns (PriceOracleResponse memory);
}
