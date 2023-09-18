// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { IWstETH } from "../Dependencies/IWstETH.sol";
import { AggregatorV3Interface, ChainlinkPriceOracle } from "./ChainlinkPriceOracle.sol";
import { IPriceOracleWstETH } from "./Interfaces/IPriceOracleWstETH.sol";

contract ChainlinkPriceOracleWstETH is IPriceOracleWstETH, ChainlinkPriceOracle {
    // --- Types ---

    using Fixed256x18 for uint256;

    // --- Immutable variables ---

    IWstETH public immutable override wstETH;

    // --- Constructor ---

    constructor(
        AggregatorV3Interface priceAggregatorAddress_,
        IWstETH wstETH_,
        uint256 deviation_,
        uint256 timeout_,
        uint256 targetDigits_,
        uint256 maxPriceDeviationFromPreviousRound_
    )
        ChainlinkPriceOracle(
            priceAggregatorAddress_,
            deviation_,
            timeout_,
            targetDigits_,
            maxPriceDeviationFromPreviousRound_
        )
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
