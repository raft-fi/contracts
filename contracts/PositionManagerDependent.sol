// SPDX-License-Identifier: MIT
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
        positionManager = positionManager_;
    }
}
