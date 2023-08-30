// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface ILock {
    /// @dev Thrown when contract usage is locked.
    error ContractLocked();

    /// @dev Unauthorized call to lock/unlock.
    error Unauthorized();

    /// @dev Retrieves if contract is currently locked or not.
    function locked() external view returns (bool);

    /// @dev Checks if a given address is whitelisted locker.
    function isWhitelistedLocker(address locker) external view returns (bool);

    /// @dev Unlcoks the usage of the contract.
    function unlock() external;

    /// @dev Locks the usage of the contract.
    function lock() external;
}
