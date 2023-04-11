// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IPriceOracle } from "../Oracles/Interfaces/IPriceOracle.sol";

interface IPriceFeed {
    // --- Errors ---

    /// @dev Invalid primary oracle.
    error InvalidPrimaryOracle();

    /// @dev Invalid secondary oracle.
    error InvalidSecondaryOracle();

    /// @dev Primary oracle is broken or frozen or bad result.
    error PrimaryOracleBrokenOrFrozenOrBadResult();

    /// @dev Invalid price difference between oracles.
    error InvalidPriceDifferenceBetweenOracles();

    // --- Events ---

    /// @dev Emitted when last good price is updated.
    event LastGoodPriceUpdated(uint256 _lastGoodPrice);

    /// @dev Emitted when price difference between oracles is updated.
    /// @param _priceDifferenceBetweenOracles New price difference between oracles.
    event PriceDifferenceBetweenOraclesUpdated(uint256 _priceDifferenceBetweenOracles);

    /// @dev Emitted when primary oracle is updated.
    /// @param _primaryOracle New primary oracle.
    event PrimaryOracleUpdated(IPriceOracle _primaryOracle);

    /// @dev Emitted when secondary oracle is updated.
    /// @param _secondaryOracle New secondary oracle.
    event SecondaryOracleUpdated(IPriceOracle _secondaryOracle);

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
    /// @param _primaryOracle Primary oracle address.
    function setPrimaryOracle(IPriceOracle _primaryOracle) external;

    /// @dev Set secondary oracle address.
    /// @param _secondaryOracle Secondary oracle address.
    function setSecondaryOracle(IPriceOracle _secondaryOracle) external;

    /// @dev Set the maximum relative price difference between two oracle responses.
    /// @param _priceDifferenceBetweenOracles The maximum relative price difference between two oracle responses.
    function setPriceDifferenceBetweenOracles(uint256 _priceDifferenceBetweenOracles) external;

    /// @dev Returns the latest price obtained from the Oracle. Called by Raft functions that require a current price.
    ///
    /// Also callable by anyone externally.
    /// Non-view function - it stores the last good price seen by Raft.
    ///
    /// Uses a primary oracle and a fallback oracle in case primary fails. If both fail,
    /// it uses the last good price seen by Raft.
    ///
    /// @return _currentPrice Returned price.
    function fetchPrice() external returns (uint256 _currentPrice);
}
