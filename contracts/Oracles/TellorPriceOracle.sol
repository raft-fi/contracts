// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IWstETH } from "../Dependencies/IWstETH.sol";
import { ITellorPriceOracle, ITellor } from "./Interfaces/ITellorPriceOracle.sol";
import { BasePriceOracle } from "./BasePriceOracle.sol";

contract TellorPriceOracle is ITellorPriceOracle, BasePriceOracle {
    // --- Constants & immutables ---

    ITellor public immutable override tellor;

    uint256 private constant TELLOR_DIGITS = 18;

    bytes32 private constant STETH_TELLOR_QUERY_ID = keccak256(abi.encode("SpotPrice", abi.encode("steth", "usd")));

    uint256 public constant override DEVIATION = 5e15; // 0.5%

    // --- Variables ---

    uint256 public override lastStoredPrice;

    uint256 public override lastStoredTimestamp;

    // --- Constructor ---

    constructor(ITellor tellor_, IWstETH wstETH_) BasePriceOracle(wstETH_) {
        if (address(tellor_) == address(0)) {
            revert InvalidTellorAddress();
        }
        tellor = ITellor(tellor_);
    }

    // --- Functions ---

    function getPriceOracleResponse() external override returns (PriceOracleResponse memory) {
        TellorResponse memory tellorResponse = _getCurrentTellorResponse();

        if (_tellorIsBroken(tellorResponse) || _oracleIsFrozen(tellorResponse.timestamp)) {
            return (PriceOracleResponse(true, false, 0));
        }
        return (PriceOracleResponse(false, false, _convertIntoWstETHPrice(tellorResponse.value, TELLOR_DIGITS)));
    }

    function _getCurrentTellorResponse() internal returns (TellorResponse memory tellorResponse) {
        uint256 time;
        uint256 value;

        try tellor.getDataBefore(STETH_TELLOR_QUERY_ID, block.timestamp - 20 minutes) returns (
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

    function _tellorIsBroken(TellorResponse memory response) internal view returns (bool) {
        return
            !response.success || response.timestamp == 0 || response.timestamp > block.timestamp || response.value == 0;
    }
}
