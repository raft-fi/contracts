// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ITellor, BaseTellorPriceOracle } from "./BaseTellorPriceOracle.sol";

contract TellorPriceOracleWETH is BaseTellorPriceOracle {
    // --- Constants & immutables ---

    uint256 public constant override DEVIATION = 5e15; // 0.5%

    // --- Constructor ---

    // solhint-disable-next-line no-empty-blocks
    constructor(ITellor tellor_, bytes32 tellorQueryId_) BaseTellorPriceOracle(tellor_, tellorQueryId_) { }

    // --- Functions ---

    function _formatPrice(uint256 price, uint256 answerDigits) internal view override returns (uint256) {
        return _scalePriceByDigits(price, answerDigits);
    }
}
