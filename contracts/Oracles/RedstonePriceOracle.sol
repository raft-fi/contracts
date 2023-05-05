// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IWstETH } from "../Dependencies/IWstETH.sol";
import { IRedstoneConsumerBase } from "./Interfaces/IRedstoneConsumerBase.sol";
import { IRedstonePriceOracle } from "./Interfaces/IRedstonePriceOracle.sol";
import { BasePriceOracle } from "./BasePriceOracle.sol";

contract RedstonePriceOracle is IRedstonePriceOracle, BasePriceOracle {
    // --- Constants ---

    uint256 public constant override DEVIATION = 0; // 0% because they fetch price in 10 seconds

    // --- Immutables ---

    IRedstoneConsumerBase public immutable override redstoneConsumerBase;

    // --- Constructor ---

    constructor(IRedstoneConsumerBase _redstoneConsumerBase, IWstETH _wstETH) BasePriceOracle(_wstETH) {
        redstoneConsumerBase = _redstoneConsumerBase;
    }

    // --- Functions ---

    function getPriceOracleResponse() external view override returns (PriceOracleResponse memory response) {
        try redstoneConsumerBase.getPrice() returns (uint256 price) {
            response.price = price;
        } catch {
            response.isBrokenOrFrozen = true;
        }
    }
}
