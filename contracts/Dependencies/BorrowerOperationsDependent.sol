// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../Interfaces/IBorrowerOperations.sol";

/// @dev Caller is not Borrower Operations.
error CallerIsNotBorrowerOperations();

contract BorrowerOperationsDependent {
    event BorrowerOperationsChanged(IBorrowerOperations _newBorrowerOperations);

    IBorrowerOperations public borrowerOperations;

    modifier onlyBorrowerOperations() {
        if (msg.sender != address(borrowerOperations)) {
            revert CallerIsNotBorrowerOperations();
        }
        _;
    }

    function setBorrowerOperations(IBorrowerOperations _borrowerOperations) internal {
        borrowerOperations = _borrowerOperations;
        emit BorrowerOperationsChanged(_borrowerOperations);
    }
}
