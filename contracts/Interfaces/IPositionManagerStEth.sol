// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IStEth} from "../Dependencies/IStEth.sol";
import {IPositionManager} from "./IPositionManager.sol";

/// @notice Interface for the StEthPositionManager contract.
interface IPositionManagerStEth is IPositionManager {
    /// @dev Send ether to contract failed.
    error SendEtherFailed();

    /// @dev Return stEth address
    function stEth() external returns (IStEth);

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

    /// @dev Manage position with stEth
    /// @param _collChange Amount of collateral to add or remove.
    /// @param _isCollIncrease True if adding collateral, false if removing.
    /// @param _rChange Amount of rToken to add or remove.
    /// @param _isDebtIncrease True if adding rToken, false if removing.
    /// @param _upperHint Address of the position with a higher collateralization ratio.
    /// @param _lowerHint Address of the position with a lower collateralization ratio.
    /// @param _maxFeePercentage Maximum fee percentage.
    function managePositionStEth(
        uint256 _collChange,
        bool _isCollIncrease,
        uint256 _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external;

    /// @dev Manage position with stEth, on behalf of a borrower
    /// @param _borrower The position to manage.
    /// @param _collChange Amount of collateral to add or remove.
    /// @param _isCollIncrease True if adding collateral, false if removing.
    /// @param _rChange Amount of rToken to add or remove.
    /// @param _isDebtIncrease True if adding rToken, false if removing.
    /// @param _upperHint Address of the position with a higher collateralization ratio.
    /// @param _lowerHint Address of the position with a lower collateralization ratio.
    /// @param _maxFeePercentage Maximum fee percentage.
    function managePositionStEth(
        address _borrower,
        uint256 _collChange,
        bool _isCollIncrease,
        uint256 _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external;
}
