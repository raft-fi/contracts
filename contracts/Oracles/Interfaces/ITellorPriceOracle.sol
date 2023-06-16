// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ITellor } from "../../Dependencies/ITellor.sol";
import { IPriceOracle } from "./IPriceOracle.sol";

interface ITellorPriceOracle is IPriceOracle {
    // --- Types ---

    struct TellorResponse {
        uint256 value;
        uint256 timestamp;
        bool success;
    }

    // --- Errors ---

    /// @dev Emitted when the Tellor address is invalid.
    error InvalidTellorAddress();

    // --- Functions ---

    /// @dev Wrapper contract that calls the Tellor system.
    function tellor() external returns (ITellor);

    /// @dev Tellor query ID.
    function tellorQueryId() external returns (bytes32);

    /// @dev Returns the last stored price from Tellor oracle
    function lastStoredPrice() external returns (uint256);

    /// @dev Returns the last stored timestamp from Tellor oracle
    function lastStoredTimestamp() external returns (uint256);
}
