// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @dev Caller is not Position Manager.
error CallerIsNotPositionManager(address caller);

interface IPositionManagerDependent {
    function positionManager() external view returns (address);
}
