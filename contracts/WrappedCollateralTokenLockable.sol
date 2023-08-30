// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { WrappedCollateralToken } from "./WrappedCollateralToken.sol";
import { Lock } from "./Lock.sol";

contract WrappedCollateralTokenLockable is Lock, WrappedCollateralToken {
    constructor(
        IERC20 underlying_,
        string memory name_,
        string memory symbol_,
        uint256 maxBalance_,
        uint256 cap_,
        address positionManager_
    )
        Lock()
        WrappedCollateralToken(underlying_, name_, symbol_, maxBalance_, cap_, positionManager_)
    { }

    function setLocker(address locker) external onlyOwner {
        _setWhitelistedLocker(locker, true);
    }

    function balanceOf(address account) public view override(IERC20, ERC20) returns (uint256) {
        if (msg.sender == positionManager && locked) {
            revert ContractLocked();
        }

        return super.balanceOf(account);
    }
}
