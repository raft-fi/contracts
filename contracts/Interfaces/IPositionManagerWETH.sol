// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IWETH } from "../Dependencies/IWETH.sol";
import { IPositionManagerDependent } from "./IPositionManagerDependent.sol";

/// @notice Interface for the PositionManagerWETH contract.
interface IPositionManagerWETH is IPositionManagerDependent {
    // --- Events ---

    /// @dev The position is changed using ETH.
    /// @param position The address of the user that has opened the position.
    /// @param collateralAmount The amount of collateral added or removed.
    /// @param isCollateralIncrease Whether the collateral is added to the position or removed from it.
    /// @param debtAmount The amount of debt added or removed.
    /// @param isDebtIncrease Whether the debt is added to the position or removed from it.
    event ETHPositionChanged(
        address indexed position,
        uint256 collateralAmount,
        bool isCollateralIncrease,
        uint256 debtAmount,
        bool isDebtIncrease
    );

    // --- Errors ---

    /// @dev The WETH address cannot be zero.
    error WETHAddressCannotBeZero();

    /// @dev Sending Ether failed.
    error SendingEtherFailed();

    // --- Functions ---

    /// @dev Returns the WETH address.
    function wETH() external view returns (IWETH);

    /// @dev Manages the position with ETH for the position (the caller).
    /// @param collateralChange The amount of ETH to add or remove.
    /// @param isCollateralIncrease True if the collateral is being increased, false otherwise.
    /// @param debtChange The amount of R to add or remove.
    /// @param isDebtIncrease True if the debt is being increased, false otherwise.
    /// @param maxFeePercentage The maximum fee percentage to pay for the position management.
    /// @param permitSignature The permit signature for the R token used for position repayment. Ignored in other
    /// cases.
    function managePositionETH(
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        ERC20PermitSignature calldata permitSignature
    )
        external
        payable;
}
