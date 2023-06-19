// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IERC20Wrapped } from "./IERC20Wrapper.sol";
import { IPositionManagerDependent } from "./IPositionManagerDependent.sol";

/// @notice Interface for the PositionManagerWrappedCollateralToken contract.
interface IPositionManagerWrappedCollateralToken is IPositionManagerDependent {
    // --- Events ---

    /// @dev The position is changed using the wrapped collateral token.
    /// @param position The address of the user that has opened the position.
    /// @param collateralAmount The amount of collateral added or removed.
    /// @param isCollateralIncrease Whether the collateral is added to the position or removed from it.
    /// @param debtAmount The amount of debt added or removed.
    /// @param isDebtIncrease Whether the debt is added to the position or removed from it.
    event WrappedCollateralTokenPositionChanged(
        address indexed position,
        uint256 collateralAmount,
        bool isCollateralIncrease,
        uint256 debtAmount,
        bool isDebtIncrease
    );

    // --- Errors ---

    /// @dev The wrapped collateral token address cannot be zero.
    error WrappedCollateralTokenAddressCannotBeZero();

    // --- Functions ---

    /// @dev Returns the wrapped collateral token address.
    function wrappedCollateralToken() external view returns (IERC20Wrapped);

    /// @dev Manages the position with the wrapped collateral token.
    /// @param collateralChange The amount of wrapped collateral token to add or remove.
    /// @param isCollateralIncrease True if the collateral is being increased, false otherwise.
    /// @param debtChange The amount of R to add or remove.
    /// @param isDebtIncrease True if the debt is being increased, false otherwise.
    /// @param maxFeePercentage The maximum fee percentage to pay for the position management.
    /// @param permitSignature The permit signature for the R token used for position repayment. Ignored in other
    /// cases.
    function managePosition(
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        ERC20PermitSignature calldata permitSignature
    )
        external;
}
