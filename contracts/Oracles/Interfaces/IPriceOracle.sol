// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface IPriceOracle {
    // --- Errors ---

    /// @dev Contract initialized with an invalid deviation parameter.
    error InvalidDeviation();

    // --- Types ---

    struct PriceOracleResponse {
        bool isBrokenOrFrozen;
        bool priceChangeAboveMax;
        uint256 price;
    }

    // --- Functions ---

    /// @dev Return price oracle response which consists the following information: oracle is broken or frozen, the
    /// price change between two rounds is more than max, and the price.
    function getPriceOracleResponse() external returns (PriceOracleResponse memory);

    /// @dev Maximum time period allowed since oracle latest round data timestamp, beyond which oracle is considered
    /// frozen.
    function TIMEOUT() external view returns (uint256);

    /// @dev Used to convert a price answer to an 18-digit precision uint.
    function TARGET_DIGITS() external view returns (uint256);

    /// @dev price deviation for the oracle in percentage.
    function DEVIATION() external view returns (uint256);
}
