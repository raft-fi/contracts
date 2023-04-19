// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IStETH} from "../Dependencies/IStETH.sol";
import {IWstETH} from "../Dependencies/IWstETH.sol";
import {IPositionManager} from "./IPositionManager.sol";

/// @notice Interface for the PositionManagerStETH contract.
interface IPositionManagerStETH is IPositionManager {
    // --- Errors ---

    /// @dev Sending ether has failed.
    error SendingEtherFailed();

    // --- Functions ---

    /// @dev Returns wstETH token.
    function wstETH() external returns (IWstETH);

    /// @dev Returns stETH token.
    function stETH() external returns (IStETH);

    /// @dev Manages the position with ether for the borrower (the caller).
    /// @param _debtChange The amount of R to add or remove.
    /// @param _isDebtIncrease True if the debt is being increased, false otherwise.
    /// @param _upperHint The upper hint for the position ID.
    /// @param _lowerHint The lower hint for the position ID.
    /// @param _maxFeePercentage The maximum fee percentage to pay for the position management.
    function managePositionETH(
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external payable;

    /// @dev Manages the position with ether on behalf of a given borrower.
    /// @param _borrower The address of the borrower.
    /// @param _debtChange The amount of R to add or remove.
    /// @param _isDebtIncrease True if the debt is being increased, false otherwise.
    /// @param _upperHint The upper hint for the position ID.
    /// @param _lowerHint The lower hint for the position ID.
    /// @param _maxFeePercentage The maximum fee percentage to pay for the position management.
    function managePositionETH(
        address _borrower,
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external payable;

    /// @dev Manages the position with stETH for the borrower (the caller).
    /// @param _collateralChange The amount of stETH to add or remove.
    /// @param _isCollateralIncrease True if the collateral is being increased, false otherwise.
    /// @param _debtChange The amount of R to add or remove.
    /// @param _isDebtIncrease True if the debt is being increased, false otherwise.
    /// @param _upperHint The upper hint for the position ID.
    /// @param _lowerHint The lower hint for the position ID.
    /// @param _maxFeePercentage The maximum fee percentage to pay for the position management.
    function managePositionStETH(
        uint256 _collateralChange,
        bool _isCollateralIncrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external;

    /// @dev Manages the position with stETH on behalf of a given borrower.
    /// @param _borrower The address of the borrower.
    /// @param _collateralChange The amount of stETH to add or remove.
    /// @param _isCollateralIncrease True if the collateral is being increased, false otherwise.
    /// @param _debtChange The amount of R to add or remove.
    /// @param _isDebtIncrease True if the debt is being increased, false otherwise.
    /// @param _upperHint The upper hint for the position ID.
    /// @param _lowerHint The lower hint for the position ID.
    /// @param _maxFeePercentage The maximum fee percentage to pay for the position management.
    function managePositionStETH(
        address _borrower,
        uint256 _collateralChange,
        bool _isCollateralIncrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external;
}
