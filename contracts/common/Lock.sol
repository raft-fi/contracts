// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ILock } from "./ILock.sol";

contract Lock is ILock {
    bool public override locked;
    address public override locker;

    constructor(address locker_) {
        locker = locker_;
        locked = true;
    }

    modifier whenUnlocked() {
        if (locked) {
            revert ContractLocked();
        }
        _;
    }

    modifier onlyLocker() {
        if (msg.sender != locker) {
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
}
