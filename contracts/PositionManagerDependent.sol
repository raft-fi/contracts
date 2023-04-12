// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IPositionManagerDependent, CallerIsNotPositionManager} from "./Interfaces/IPositionManagerDependent.sol";

abstract contract PositionManagerDependent is IPositionManagerDependent {
    address public immutable override positionManager;

    modifier onlyPositionManager() {
        if (msg.sender != positionManager) {
            revert CallerIsNotPositionManager(msg.sender);
        }
        _;
    }

    constructor(address _positionManager) {
        positionManager = _positionManager;
    }
}
