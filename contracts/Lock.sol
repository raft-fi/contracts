// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ILock } from "./Interfaces/ILock.sol";

contract Lock is ILock {
    bool public override locked;
    mapping(address => bool) public override isWhitelistedLocker;

    constructor() {
        locked = true;
    }

    modifier whenUnlocked() {
        if (locked) {
            revert ContractLocked();
        }
        _;
    }

    modifier onlyLocker() {
        if (!isWhitelistedLocker[msg.sender]) {
            revert Unauthorized();
        }
        _;
    }

    function unlock() external override onlyLocker {
        locked = false;
    }

    function lock() public onlyLocker {
        locked = true;
    }

    function _setWhitelistedLocker(address locker, bool isWhitelisted) internal {
        isWhitelistedLocker[locker] = isWhitelisted;
    }
}
