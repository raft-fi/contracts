// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./Interfaces/ITellorPriceOracle.sol";
import "./BasePriceOracle.sol";

contract TellorPriceOracle is ITellorPriceOracle, BasePriceOracle {

    ITellor public immutable override tellor;
    
    uint256 constant private TELLOR_DIGITS = 6;
    
    uint256 constant private ETHUSD_TELLOR_REQ_ID = 1;

    constructor(ITellor _tellor) {
        if (address(_tellor) == address(0)) {
            revert InvalidTellorAddress();
        }
        tellor = ITellor(_tellor);
    }

    function getPriceOracleResponse() external override view returns(PriceOracleResponse memory) {
        TellorResponse memory _tellorResponse = _getCurrentTellorResponse();

        if (_tellorIsBroken(_tellorResponse) || _oracleIsFrozen(_tellorResponse.timestamp)) {
            return(PriceOracleResponse(true, false, 0));
        }
        return (PriceOracleResponse(
            false,
            false,
           _scalePriceByDigits(_tellorResponse.value, TELLOR_DIGITS)
        ));
    }

    function _getCurrentTellorResponse() internal view returns (TellorResponse memory tellorResponse) {
        uint256 _count;
        uint256 _time;
        uint256 _value;

        try tellor.getNewValueCountbyRequestId(ETHUSD_TELLOR_REQ_ID) returns (uint256 count) {
            _count = count;
        } catch {
            return (tellorResponse);
        }

        try tellor.getTimestampbyRequestIDandIndex(ETHUSD_TELLOR_REQ_ID, _count - 1) returns (uint256 time) {
            _time = time;
        } catch {
            return (tellorResponse);
        }

        try tellor.retrieveData(ETHUSD_TELLOR_REQ_ID, _time) returns (uint256 value) {
            _value = value;
        } catch {
            return (tellorResponse);
        }

        tellorResponse.isRetrieved = _value > 0;
        tellorResponse.value = _value;
        tellorResponse.timestamp = _time;
        tellorResponse.success = true;
    }

    function _tellorIsBroken(TellorResponse memory _response) internal view returns (bool) {
        return !_response.success || _response.timestamp == 0 || _response.timestamp > block.timestamp || _response.value == 0;
    }
}
