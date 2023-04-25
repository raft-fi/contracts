// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IPositionManagerDependent } from "./IPositionManagerDependent.sol";
import { IStETH } from "../Dependencies/IStETH.sol";
import { IWstETH } from "../Dependencies/IWstETH.sol";

/// @notice Interface for the PositionManagerStETH contract.
interface IPositionManagerStETH is IPositionManagerDependent {
    // --- Errors ---

    /// @dev Invalid wstETH address.
    error WstETHAddressCannotBeZero();

    /// @dev Sending ether has failed.
    error SendingEtherFailed();

    // --- Functions ---

    /// @dev Returns wstETH token.
    function wstETH() external returns (IWstETH);

    /// @dev Returns stETH token.
    function stETH() external returns (IStETH);

    /// @dev Manages the position with ether for the position (the caller).
    /// @param debtChange The amount of R to add or remove.
    /// @param isDebtIncrease True if the debt is being increased, false otherwise.
    /// @param maxFeePercentage The maximum fee percentage to pay for the position management.
    function managePositionETH(uint256 debtChange, bool isDebtIncrease, uint256 maxFeePercentage) external payable;

    /// @dev Manages the position with stETH for the position (the caller).
    /// @param collateralChange The amount of stETH to add or remove.
    /// @param isCollateralIncrease True if the collateral is being increased, false otherwise.
    /// @param debtChange The amount of R to add or remove.
    /// @param isDebtIncrease True if the debt is being increased, false otherwise.
    /// @param maxFeePercentage The maximum fee percentage to pay for the position management.
    function managePositionStETH(
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage
    )
        external;
}
