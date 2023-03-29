// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./Interfaces/IPositionManager.sol";
import "./Interfaces/IPositionManagerDependent.sol";

/// @dev Caller is not Position Manager.
error CallerIsNotPositionManager(address caller);

abstract contract PositionManagerDependent is IPositionManagerDependent {
    IPositionManager public immutable override positionManager;

    modifier onlyPositionManager() {
        if (msg.sender != address(positionManager)) {
            revert CallerIsNotPositionManager(msg.sender);
        }
        _;
    }

    constructor(IPositionManager _positionManager) {
        positionManager = _positionManager;
    }
}
