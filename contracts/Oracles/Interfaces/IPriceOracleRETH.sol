// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IPriceFeed } from "../../Interfaces/IPriceFeed.sol";
import { IPriceOracle } from "./IPriceOracle.sol";

interface IPriceOracleRETH is IPriceOracle {
    // --- Errors ---

    /// @dev Invalid price feed ETH address.
    error InvalidPriceFeedETHAddress();

    // --- Functions ---

    /// @dev Return price feed ETH address.
    function priceFeedETH() external view returns (IPriceFeed);
}
