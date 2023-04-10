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

    // --- Events ---

    /// @dev Emitted when last good price is updated.
    event LastGoodPriceUpdated(uint256 _lastGoodPrice);

    // --- Functions ---

    /// @dev Return primary oracle address.
    function primaryOracle() external returns (IPriceOracle);

    /// @dev Return secondary oracle address
    function secondaryOracle() external returns (IPriceOracle);

    /// @dev The last good price seen from an oracle by Raft.
    function lastGoodPrice() external returns (uint256);

    /// @dev The maximum relative price difference between two oracle responses.
    function MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES() external returns (uint256);

    /// @dev Set primary oracle address.
    /// @param _primaryOracle Primary oracle address.
    function setPrimaryOracle(IPriceOracle _primaryOracle) external;

    /// @dev Set secondary oracle address.
    /// @param _secondaryOracle Secondary oracle address.
    function setSecondaryOracle(IPriceOracle _secondaryOracle) external;

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
