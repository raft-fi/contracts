// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { IPriceFeed } from "../Interfaces/IPriceFeed.sol";
import { IPriceOracleRETH } from "./Interfaces/IPriceOracleRETH.sol";
import { AggregatorV3Interface, ChainlinkPriceOracle } from "./ChainlinkPriceOracle.sol";

contract ChainlinkPriceOracleRETH is ChainlinkPriceOracle, IPriceOracleRETH {
    // --- Types ---

    using Fixed256x18 for uint256;

    // --- Immutables ---

    IPriceFeed public immutable override priceFeedETH;

    // --- Constructor ---

    constructor(
        AggregatorV3Interface priceAggregatorAddress_,
        IPriceFeed priceFeedETH_,
        uint256 deviation_,
        uint256 timeout_
    )
        ChainlinkPriceOracle(priceAggregatorAddress_, deviation_, timeout_)
    {
        if (address(priceFeedETH_) == address(0)) {
            revert InvalidPriceFeedETHAddress();
        }
        priceFeedETH = priceFeedETH_;
    }

    function _formatPrice(uint256 price, uint256 answerDigits) internal override returns (uint256) {
        (uint256 ethUsdPrice,) = priceFeedETH.fetchPrice();
        return super._formatPrice(price, answerDigits).mulDown(ethUsdPrice);
    }
}
