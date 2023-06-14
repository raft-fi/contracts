// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IWstETH } from "../../Dependencies/IWstETH.sol";
import { IPriceOracle } from "./IPriceOracle.sol";

interface IPriceOracleWstETH is IPriceOracle {
    // --- Errors ---

    /// @dev Invalid wstETH address.
    error InvalidWstETHAddress();

    // --- Functions ---

    /// @dev Return wstETH address.
    function wstETH() external view returns (IWstETH);
}
