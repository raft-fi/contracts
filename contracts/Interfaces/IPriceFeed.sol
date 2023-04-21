// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IPriceOracle} from "../Oracles/Interfaces/IPriceOracle.sol";

interface IPriceFeed {
    // --- Events ---

    /// @dev Last good price has been updated.
    event LastGoodPriceUpdated(uint256 lastGoodPrice);

    /// @dev Price difference between oracles has been updated.
    /// @param priceDifferenceBetweenOracles New price difference between oracles.
    event PriceDifferenceBetweenOraclesUpdated(uint256 priceDifferenceBetweenOracles);

    /// @dev Primary oracle has been updated.
    /// @param primaryOracle New primary oracle.
    event PrimaryOracleUpdated(IPriceOracle primaryOracle);

    /// @dev Secondary oracle has been updated.
    /// @param secondaryOracle New secondary oracle.
    event SecondaryOracleUpdated(IPriceOracle secondaryOracle);

    // --- Errors ---

    /// @dev Invalid primary oracle.
    error InvalidPrimaryOracle();

    /// @dev Invalid secondary oracle.
    error InvalidSecondaryOracle();

    /// @dev Primary oracle is broken or frozen or has bad result.
    error PrimaryOracleBrokenOrFrozenOrBadResult();

    /// @dev Invalid price difference between oracles.
    error InvalidPriceDifferenceBetweenOracles();

    // --- Functions ---

    /// @dev Return primary oracle address.
    function primaryOracle() external returns (IPriceOracle);

    /// @dev Return secondary oracle address
    function secondaryOracle() external returns (IPriceOracle);

    /// @dev The last good price seen from an oracle by Raft.
    function lastGoodPrice() external returns (uint256);

    /// @dev The maximum relative price difference between two oracle responses.
    function priceDifferenceBetweenOracles() external returns (uint256);

    /// @dev Set primary oracle address.
    /// @param newPrimaryOracle Primary oracle address.
    function setPrimaryOracle(IPriceOracle newPrimaryOracle) external;

    /// @dev Set secondary oracle address.
    /// @param newSecondaryOracle Secondary oracle address.
    function setSecondaryOracle(IPriceOracle newSecondaryOracle) external;

    /// @dev Set the maximum relative price difference between two oracle responses.
    /// @param newPriceDifferenceBetweenOracles The maximum relative price difference between two oracle responses.
    function setPriceDifferenceBetweenOracles(uint256 newPriceDifferenceBetweenOracles) external;

    /// @dev Returns the latest price obtained from the Oracle. Called by Raft functions that require a current price.
    ///
    /// Also callable by anyone externally.
    /// Non-view function - it stores the last good price seen by Raft.
    ///
    /// Uses a primary oracle and a fallback oracle in case primary fails. If both fail,
    /// it uses the last good price seen by Raft.
    ///
    /// @return currentPrice Returned price.
    function fetchPrice() external returns (uint256 currentPrice);
}
