// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface ILock {
    /// @dev Thrown when contract usage is locked.
    error ContractLocked();

    /// @dev Unauthorized call to lock/unlock.
    error Unauthorized();

    /// @dev Retrieves if contract is currently locked or not.
    function locked() external view returns (bool);

    /// @dev Retrieves address of the locker who can unlock contract.
    function locker() external view returns (address);

    /// @dev Unlcoks the usage of the contract.
    function unlock() external;

    /// @dev Locks the usage of the contract.
    function lock() external;
}
