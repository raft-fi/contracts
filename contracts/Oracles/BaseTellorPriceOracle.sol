// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ITellor, ITellorPriceOracle } from "./Interfaces/ITellorPriceOracle.sol";

abstract contract BaseTellorPriceOracle is ITellorPriceOracle {
    // --- Constants & immutables ---

    ITellor public immutable override tellor;

    // --- Variables ---

    uint256 public override lastStoredPrice;

    uint256 public override lastStoredTimestamp;

    // --- Constructor ---

    constructor(ITellor tellor_) {
        if (address(tellor_) == address(0)) {
            revert InvalidTellorAddress();
        }
        tellor = ITellor(tellor_);
    }

    // --- Functions ---

    function _tellorIsBroken(TellorResponse memory response) internal view returns (bool) {
        return
            !response.success || response.timestamp == 0 || response.timestamp > block.timestamp || response.value == 0;
    }

    function _getCurrentTellorResponse(bytes32 queryId) internal returns (TellorResponse memory tellorResponse) {
        uint256 time;
        uint256 value;

        try tellor.getDataBefore(queryId, block.timestamp - 20 minutes) returns (
            bool, bytes memory data, uint256 timestamp
        ) {
            value = abi.decode(data, (uint256));
            time = timestamp;
        } catch {
            return (tellorResponse);
        }

        if (time > lastStoredTimestamp) {
            lastStoredPrice = value;
            lastStoredTimestamp = time;
        }
        return TellorResponse(lastStoredPrice, lastStoredTimestamp, true);
    }
}
