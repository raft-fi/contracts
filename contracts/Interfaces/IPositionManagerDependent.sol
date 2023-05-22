// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface IPositionManagerDependent {
    // --- Errors ---

    /// @dev Position Manager cannot be zero.
    error PositionManagerCannotBeZero();

    /// @dev Caller is not Position Manager.
    error CallerIsNotPositionManager(address caller);

    // --- Functions ---

    /// @dev Returns address of the PositionManager contract.
    function positionManager() external view returns (address);
}
