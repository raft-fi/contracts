// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IStETH } from "../Dependencies/IStETH.sol";
import { IWstETH } from "../Dependencies/IWstETH.sol";

interface IWstETHWrapper {
    /// @dev Invalid wstETH address.
    error WstETHAddressCannotBeZero();

    /// @dev Returns wstETH token.
    function wstETH() external view returns (IWstETH);

    /// @dev Returns stETH token.
    function stETH() external view returns (IStETH);
}
