// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPositionManagerDependent {
    // --- Errors ---

    /// @dev Caller is not Position Manager.
    error CallerIsNotPositionManager(address caller);

    // --- Functions ---

    /// @dev Returns address of the PositionManager contract.
    function positionManager() external view returns (address);
}
