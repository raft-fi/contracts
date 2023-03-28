// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../Interfaces/ITroveManager.sol";

/// @dev Caller is not Borrower Operations.
error CallerIsNotTroveManager();

contract TroveManagerDependent {
    event TroveManagerChanged(ITroveManager _newTroveManager);

    ITroveManager public troveManager;

    modifier onlyTroveManager() {
        if (msg.sender != address(troveManager)) {
            revert CallerIsNotTroveManager();
        }
        _;
    }

    function setTroveManager(ITroveManager _troveManager) internal {
        troveManager = _troveManager;
        emit TroveManagerChanged(_troveManager);
    }
}
