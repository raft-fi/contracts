// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IOneStepLeverage } from "./IOneStepLeverage.sol";

/// @dev Interface that OneStepLeverage needs to implement
interface IOneStepLeverageStETH is IOneStepLeverage {
    /// @dev Thrown when `manageLeveragedPositionETH` is invoked without passing any ETH value (msg.value == 0).
    error NoETHProvided();

    /// @dev Increases or decreases leverage for a position. Allows stETH deposits.
    /// @param debtChange Debt being added or removed.
    /// @param isDebtIncrease True if increasing debt/leverage.
    /// @param stETHCollateralChange stETH collateral change (collateral added/removed from/to user wallet)
    /// @param stETHCollateralIncrease True if stETH is added.
    /// @param ammData Additional data to pass to swap method in amm.
    /// @param minReturnOrAmountToSell Serves for two different purposes:
    /// - leverage increase: it is min amount of collateral token to get from swapping flash minted R.
    /// - leverage decrease: it is amount of collateral to swap that will result with enough R to repay flash mint.
    /// @param maxFeePercentage The maximum fee percentage to pay for the position management.
    /// @notice In case of closing position by decreasing debt to zero principalCollIncrease must be false,
    /// and principalCollChange + minReturnOrAmountToSell should be equal to total collateral balance of user.
    function manageLeveragedPositionStETH(
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 stETHCollateralChange,
        bool stETHCollateralIncrease,
        bytes calldata ammData,
        uint256 minReturnOrAmountToSell,
        uint256 maxFeePercentage
    )
        external;

    /// @dev Increases or decreases leverage for a position. Allows ETH deposits.
    /// @param debtChange Debt being added or removed.
    /// @param isDebtIncrease True if increasing debt/leverage.
    /// @param ammData Additional data to pass to swap method in amm.
    /// @param minReturnOrAmountToSell Serves for two different purposes:
    /// - leverage increase: it is min amount of collateral token to get from swapping flash minted R.
    /// - leverage decrease: it is amount of collateral to swap that will result with enough R to repay flash mint.
    /// @param maxFeePercentage The maximum fee percentage to pay for the position management.
    function manageLeveragedPositionETH(
        uint256 debtChange,
        bool isDebtIncrease,
        bytes calldata ammData,
        uint256 minReturnOrAmountToSell,
        uint256 maxFeePercentage
    )
        external
        payable;
}
