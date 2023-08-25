// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20WrappedLockable } from "./Interfaces/IERC20WrappedLockable.sol";
import { WrappedCollateralToken } from "./WrappedCollateralToken.sol";

contract WrappedCollateralTokenLockable is IERC20WrappedLockable, WrappedCollateralToken {
    bool public override isLocked = true;

    error ContractLocked();

    constructor(
        IERC20 underlying_,
        string memory name_,
        string memory symbol_,
        uint256 maxBalance_,
        uint256 cap_,
        address positionManager_
    )
        WrappedCollateralToken(underlying_, name_, symbol_, maxBalance_, cap_, positionManager_)
    { }

    function setLock(bool lock) external override checkWhitelist {
        isLocked = lock;
    }

    function balanceOf(address account) public view override(IERC20, ERC20) returns (uint256) {
        if (msg.sender == positionManager && isLocked) {
            revert ContractLocked();
        }

        return super.balanceOf(account);
    }
}
