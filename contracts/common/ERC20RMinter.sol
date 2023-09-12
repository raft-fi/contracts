// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IRToken } from "../Interfaces/IRToken.sol";
import { IPositionManager } from "../Interfaces/IPositionManager.sol";
import { IRMinter } from "./IERC20RMinter.sol";
import { ILock } from "./ILock.sol";

abstract contract ERC20RMinter is IRMinter, ERC20, Ownable2Step {
    using SafeERC20 for IERC20;

    IRToken public immutable override r;
    IPositionManager public immutable override positionManager;

    constructor(IRToken rToken_, string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        r = rToken_;
        positionManager = IPositionManager(rToken_.positionManager());

        _approve(address(this), address(positionManager), type(uint256).max);
    }

    modifier unlockCall() {
        ILock lockContract = ILock(address(positionManager.priceFeed(IERC20(this))));
        lockContract.unlock();
        _;
        lockContract.lock();
    }

    function recoverTokens(IERC20 token, address to, uint256 amount) external override onlyOwner {
        token.safeTransfer(to, amount);
        emit TokensRecovered(token, to, amount);
    }

    function _mintR(address to, uint256 amount) internal unlockCall {
        _mint(address(this), amount);
        ERC20PermitSignature memory emptySignature;
        positionManager.managePosition(
            IERC20(address(this)),
            address(this),
            amount,
            true, // collateral increase
            amount,
            true, // debt increase
            1e18, // 100%
            emptySignature
        );
        r.transfer(to, amount);
    }

    function _burnR(address from, uint256 amount) internal unlockCall {
        r.transferFrom(from, address(this), amount);
        ERC20PermitSignature memory emptySignature;
        positionManager.managePosition(
            IERC20(address(this)),
            address(this),
            amount,
            false, // collateral decrease
            amount,
            false, // debt decrease
            1e18, // 100%
            emptySignature
        );
        _burn(address(this), amount);
    }
}
