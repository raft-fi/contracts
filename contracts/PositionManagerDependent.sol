// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IPositionManagerDependent } from "./Interfaces/IPositionManagerDependent.sol";

abstract contract PositionManagerDependent is IPositionManagerDependent {
    // --- Immutable variables ---

    address public immutable override positionManager;

    // --- Modifiers ---

    modifier onlyPositionManager() {
        if (msg.sender != positionManager) {
            revert CallerIsNotPositionManager(msg.sender);
        }
        _;
    }

    // --- Constructor ---

    constructor(address positionManager_) {
        if (positionManager_ == address(0)) {
            revert PositionManagerCannotBeZero();
        }
        positionManager = positionManager_;
    }
}
