// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IWstETH} from "../Dependencies/IWstETH.sol";
import {ITellorPriceOracle, ITellor} from "./Interfaces/ITellorPriceOracle.sol";
import {BasePriceOracle} from "./BasePriceOracle.sol";

contract TellorPriceOracle is ITellorPriceOracle, BasePriceOracle {
    // --- Constants & immutables ---

    ITellor public immutable override tellor;

    uint256 private constant TELLOR_DIGITS = 6;

    uint256 private constant ETHUSD_TELLOR_REQ_ID = 1;

    // --- Constructor ---

    constructor(ITellor tellor_, IWstETH wstETH_) BasePriceOracle(wstETH_) {
        if (address(tellor_) == address(0)) {
            revert InvalidTellorAddress();
        }
        tellor = ITellor(tellor_);
    }

    // --- Functions ---

    function getPriceOracleResponse() external view override returns (PriceOracleResponse memory) {
        TellorResponse memory tellorResponse = _getCurrentTellorResponse();

        if (_tellorIsBroken(tellorResponse) || _oracleIsFrozen(tellorResponse.timestamp)) {
            return (PriceOracleResponse(true, false, 0));
        }
        return (PriceOracleResponse(false, false, _convertIntoWstETHPrice(tellorResponse.value, TELLOR_DIGITS)));
    }

    function _getCurrentTellorResponse() internal view returns (TellorResponse memory tellorResponse) {
        uint256 count;
        uint256 time;
        uint256 value;

        try tellor.getNewValueCountbyRequestId(ETHUSD_TELLOR_REQ_ID) returns (uint256 count_) {
            count = count_;
        } catch {
            return (tellorResponse);
        }

        try tellor.getTimestampbyRequestIDandIndex(ETHUSD_TELLOR_REQ_ID, count - 1) returns (uint256 time_) {
            time = time_;
        } catch {
            return (tellorResponse);
        }

        try tellor.retrieveData(ETHUSD_TELLOR_REQ_ID, time) returns (uint256 value_) {
            value = value_;
        } catch {
            return (tellorResponse);
        }

        tellorResponse.isRetrieved = value > 0;
        tellorResponse.value = value;
        tellorResponse.timestamp = time;
        tellorResponse.success = true;
    }

    function _tellorIsBroken(TellorResponse memory response) internal view returns (bool) {
        return
            !response.success || response.timestamp == 0 || response.timestamp > block.timestamp || response.value == 0;
    }
}
