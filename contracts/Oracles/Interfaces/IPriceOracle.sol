// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IWstETH } from "../../Dependencies/IWstETH.sol";

interface IPriceOracle {
    // --- Types ---

    struct PriceOracleResponse {
        bool isBrokenOrFrozen;
        bool priceChangeAboveMax;
        uint256 price;
    }

    // --- Errors ---

    /// @dev Invalid wstETH address.
    error InvalidWstETHAddress();

    // --- Functions ---

    /// @dev Return price oracle response which consists the following information: oracle is broken or frozen, the
    /// price change between two rounds is more than max, and the price.
    function getPriceOracleResponse() external returns (PriceOracleResponse memory);

    /// @dev Return wstETH address.
    function wstETH() external view returns (IWstETH);

    /// @dev Maximum time period allowed since oracle latest round data timestamp, beyond which oracle is considered
    /// frozen.
    function TIMEOUT() external view returns (uint256);

    /// @dev Used to convert a price answer to an 18-digit precision uint.
    function TARGET_DIGITS() external view returns (uint256);

    /// @dev price deviation for the oracle in percentage.
    function DEVIATION() external view returns (uint256);
}
