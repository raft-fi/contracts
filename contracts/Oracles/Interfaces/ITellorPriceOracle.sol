// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ITellor } from "../../Dependencies/ITellor.sol";
import { IPriceOracle } from "./IPriceOracle.sol";

interface ITellorPriceOracle is IPriceOracle {
    // --- Types ---

    struct TellorResponse {
        bool isRetrieved;
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
}
