// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IPositionManagerDependent } from "./IPositionManagerDependent.sol";
import { IWstETHWrapper } from "./IWstETHWrapper.sol";

/// @notice Interface for the PositionManagerStETH contract.
interface IPositionManagerStETH is IPositionManagerDependent, IWstETHWrapper {
    // --- Functions ---

    /// @dev Manages the position with ether for the position (the caller).
    /// @param debtChange The amount of R to add or remove.
    /// @param isDebtIncrease True if the debt is being increased, false otherwise.
    /// @param maxFeePercentage The maximum fee percentage to pay for the position management.
    /// @param permitSignature The permit signature for the R token used for position repayment. Ignored in other
    /// cases.
    function managePositionETH(
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        ERC20PermitSignature calldata permitSignature
    )
        external
        payable;

    /// @dev Manages the position with stETH for the position (the caller).
    /// @param collateralChange The amount of stETH to add or remove.
    /// @param isCollateralIncrease True if the collateral is being increased, false otherwise.
    /// @param debtChange The amount of R to add or remove.
    /// @param isDebtIncrease True if the debt is being increased, false otherwise.
    /// @param maxFeePercentage The maximum fee percentage to pay for the position management.
    /// @param permitSignature The permit signature for the R token used for position repayment. Ignored in other
    /// cases.
    function managePositionStETH(
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        ERC20PermitSignature calldata permitSignature
    )
        external;
}
