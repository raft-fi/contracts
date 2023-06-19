// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IWstETH } from "../Dependencies/IWstETH.sol";
import { BasePriceOracleWstETH } from "./BasePriceOracleWstETH.sol";
import { ITellor, TellorPriceOracle } from "./TellorPriceOracle.sol";
import { IPriceOracleWstETH } from "./Interfaces/IPriceOracleWstETH.sol";

contract TellorPriceOracleWstETH is IPriceOracleWstETH, BasePriceOracleWstETH, TellorPriceOracle {
    // --- Constructor ---

    constructor(
        ITellor tellor_,
        bytes32 tellorQueryId_,
        IWstETH wstETH_,
        uint256 deviation_
    )
        BasePriceOracleWstETH(wstETH_)
        TellorPriceOracle(tellor_, tellorQueryId_, deviation_)
    // solhint-disable-next-line no-empty-blocks
    { }

    function _formatPrice(uint256 price, uint256 answerDigits) internal view override returns (uint256) {
        return _convertIntoWstETHPrice(price, answerDigits);
    }
}
