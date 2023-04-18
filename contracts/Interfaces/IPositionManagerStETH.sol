// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IStETH} from "../Dependencies/IStETH.sol";
import {IWstETH} from "../Dependencies/IWstETH.sol";
import {IPositionManager} from "./IPositionManager.sol";

/// @notice Interface for the PositionManagerStETH contract.
interface IPositionManagerStETH is IPositionManager {
    // --- Errors ---

    /// @dev Send ether to contract failed.
    error SendEtherFailed();

    // --- Functions ---

    /// @dev Return wstETH address
    function wstETH() external returns (IWstETH);

    /// @dev Return stETH address
    function stETH() external returns (IStETH);

    /// @dev Manage position with ether
    /// @param _rChange Amount of rToken to add or remove.
    /// @param _isDebtIncrease True if adding rToken, false if removing.
    /// @param _upperHint Address of the position with a higher collateralization ratio.
    /// @param _lowerHint Address of the position with a lower collateralization ratio.
    /// @param _maxFeePercentage Maximum fee percentage.
    function managePositionEth(
        uint256 _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external payable;

    /// @dev Manage position with ether, on behalf of a borrower
    /// @param _borrower The position to manage.
    /// @param _rChange Amount of rToken to add or remove.
    /// @param _isDebtIncrease True if adding rToken, false if removing.
    /// @param _upperHint Address of the position with a higher collateralization ratio.
    /// @param _lowerHint Address of the position with a lower collateralization ratio.
    /// @param _maxFeePercentage Maximum fee percentage.
    function managePositionEth(
        address _borrower,
        uint256 _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external payable;

    /// @dev Manage position with stETH
    /// @param _collateralChange Amount of collateral to add or remove.
    /// @param _isCollateralIncrease True if adding collateral, false if removing.
    /// @param _rChange Amount of rToken to add or remove.
    /// @param _isDebtIncrease True if adding rToken, false if removing.
    /// @param _upperHint Address of the position with a higher collateralization ratio.
    /// @param _lowerHint Address of the position with a lower collateralization ratio.
    /// @param _maxFeePercentage Maximum fee percentage.
    function managePositionStETH(
        uint256 _collateralChange,
        bool _isCollateralIncrease,
        uint256 _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external;

    /// @dev Manage position with stETH, on behalf of a borrower
    /// @param _borrower The position to manage.
    /// @param _collateralChange Amount of collateral to add or remove.
    /// @param _isCollateralIncrease True if adding collateral, false if removing.
    /// @param _rChange Amount of rToken to add or remove.
    /// @param _isDebtIncrease True if adding rToken, false if removing.
    /// @param _upperHint Address of the position with a higher collateralization ratio.
    /// @param _lowerHint Address of the position with a lower collateralization ratio.
    /// @param _maxFeePercentage Maximum fee percentage.
    function managePositionStETH(
        address _borrower,
        uint256 _collateralChange,
        bool _isCollateralIncrease,
        uint256 _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external;
}
