// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ITellor, ITellorPriceOracle } from "./Interfaces/ITellorPriceOracle.sol";
import { BasePriceOracle } from "./BasePriceOracle.sol";

abstract contract BaseTellorPriceOracle is BasePriceOracle, ITellorPriceOracle {
    // --- Constants & immutables ---

    uint256 private constant _TELLOR_DIGITS = 18;

    ITellor public immutable override tellor;

    bytes32 public immutable override tellorQueryId;

    // --- Variables ---

    uint256 public override lastStoredPrice;

    uint256 public override lastStoredTimestamp;

    // --- Constructor ---

    constructor(ITellor tellor_, bytes32 tellorQueryId_) {
        if (address(tellor_) == address(0)) {
            revert InvalidTellorAddress();
        }
        tellor = ITellor(tellor_);
        tellorQueryId = tellorQueryId_;
    }

    // --- Functions ---

    function getPriceOracleResponse() external override returns (PriceOracleResponse memory) {
        TellorResponse memory tellorResponse = _getCurrentTellorResponse(tellorQueryId);

        if (_tellorIsBroken(tellorResponse) || _oracleIsFrozen(tellorResponse.timestamp)) {
            return (PriceOracleResponse(true, false, 0));
        }
        return (PriceOracleResponse(false, false, _formatPrice(tellorResponse.value, _TELLOR_DIGITS)));
    }

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

    function _formatPrice(uint256 price, uint256 answerDigits) internal view virtual returns (uint256);
}
