// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IPriceOracle } from "./IPriceOracle.sol";
import { IRedstoneConsumerBase } from "./IRedstoneConsumerBase.sol";

interface IRedstonePriceOracle is IPriceOracle {
    // --- Functions ---

    /// @dev Return redstone consumer base address.
    function redstoneConsumerBase() external view returns (IRedstoneConsumerBase);
}
