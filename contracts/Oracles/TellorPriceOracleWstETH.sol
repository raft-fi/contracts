// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IWstETH } from "../Dependencies/IWstETH.sol";
import { ITellor, BaseTellorPriceOracle } from "./BaseTellorPriceOracle.sol";
import { BasePriceOracleWstETH } from "./BasePriceOracleWstETH.sol";

contract TellorPriceOracleWstETH is BaseTellorPriceOracle, BasePriceOracleWstETH {
    // --- Constants & immutables ---

    uint256 public constant override DEVIATION = 5e15; // 0.5%

    // --- Constructor ---

    constructor(
        ITellor tellor_,
        bytes32 tellorQueryId_,
        IWstETH wstETH_
    )
        BaseTellorPriceOracle(tellor_, tellorQueryId_)
        BasePriceOracleWstETH(wstETH_)
    // solhint-disable-next-line no-empty-blocks
    { }

    // --- Functions ---

    function _formatPrice(uint256 price, uint256 answerDigits) internal view override returns (uint256) {
        return _convertIntoWstETHPrice(price, answerDigits);
    }
}
