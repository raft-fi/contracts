// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { IWstETH } from "../Dependencies/IWstETH.sol";
import { ITellor, TellorPriceOracle } from "./TellorPriceOracle.sol";
import { IPriceOracleWstETH } from "./Interfaces/IPriceOracleWstETH.sol";

contract TellorPriceOracleWstETH is IPriceOracleWstETH, TellorPriceOracle {
    // --- Types ---

    using Fixed256x18 for uint256;

    // --- Immutable variables ---

    IWstETH public immutable override wstETH;

    // --- Constructor ---

    constructor(
        ITellor tellor_,
        bytes32 tellorQueryId_,
        IWstETH wstETH_,
        uint256 deviation_,
        uint256 timeout_,
        uint256 targetDigits_
    )
        TellorPriceOracle(tellor_, tellorQueryId_, deviation_, timeout_, targetDigits_)
    {
        if (address(wstETH_) == address(0)) {
            revert InvalidWstETHAddress();
        }
        wstETH = IWstETH(wstETH_);
    }

    function _formatPrice(uint256 price, uint256 answerDigits) internal override returns (uint256) {
        return super._formatPrice(price, answerDigits).mulDown(wstETH.stEthPerToken());
    }
}
