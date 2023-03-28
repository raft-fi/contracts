// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../Interfaces/IPositionManager.sol";

/// @dev Caller is not Borrower Operations.
error CallerIsNotPositionManager();

contract PositionManagerDependent {
    event PositionManagerChanged(IPositionManager _newPositionManager);

    IPositionManager public positionManager;

    modifier onlyPositionManager() {
        if (msg.sender != address(positionManager)) {
            revert CallerIsNotPositionManager();
        }
        _;
    }

    function setPositionManager(IPositionManager _positionManager) internal {
        positionManager = _positionManager;
        emit PositionManagerChanged(_positionManager);
    }
}
