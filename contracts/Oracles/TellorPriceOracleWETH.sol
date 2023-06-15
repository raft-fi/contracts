// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ITellor, BaseTellorPriceOracle } from "./BaseTellorPriceOracle.sol";
import { BasePriceOracle } from "./BasePriceOracle.sol";

contract TellorPriceOracleWETH is BaseTellorPriceOracle, BasePriceOracle {
    // --- Constants & immutables ---

    uint256 public constant override DEVIATION = 5e15; // 0.5%

    uint256 private constant _TELLOR_DIGITS = 18;

    bytes32 private constant _WETH_TELLOR_QUERY_ID = keccak256(abi.encode("SpotPrice", abi.encode("eth", "usd")));

    // --- Constructor ---

    // solhint-disable-next-line no-empty-blocks
    constructor(ITellor tellor_) BaseTellorPriceOracle(tellor_) { }

    // --- Functions ---

    function getPriceOracleResponse() external override returns (PriceOracleResponse memory) {
        TellorResponse memory tellorResponse = _getCurrentTellorResponse(_WETH_TELLOR_QUERY_ID);

        if (_tellorIsBroken(tellorResponse) || _oracleIsFrozen(tellorResponse.timestamp)) {
            return (PriceOracleResponse(true, false, 0));
        }
        return (PriceOracleResponse(false, false, _scalePriceByDigits(tellorResponse.value, _TELLOR_DIGITS)));
    }
}
