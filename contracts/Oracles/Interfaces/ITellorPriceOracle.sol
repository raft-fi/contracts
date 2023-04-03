// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../Dependencies/ITellor.sol";
import "./IPriceOracle.sol";

error InvalidTellorAddress();

struct TellorResponse {
    bool isRetrieved;
    uint256 value;
    uint256 timestamp;
    bool success;
}

interface ITellorPriceOracle is IPriceOracle {
    /// @dev Wrapper contract that calls the Tellor system.
    function tellor() external returns(ITellor);
}
