// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PermitSignature, PermitHelper } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IStETH } from "./Dependencies/IStETH.sol";
import { IWstETH } from "./Dependencies/IWstETH.sol";
import { IERC20Indexable } from "./Interfaces/IERC20Indexable.sol";
import { IERC20Wrapped } from "./Interfaces/IERC20Wrapped.sol";
import { IPositionManager } from "./Interfaces/IPositionManager.sol";
import { IRToken } from "./Interfaces/IRToken.sol";
import { IPositionManagerWrappedCollateralToken } from "./Interfaces/IPositionManagerWrappedCollateralToken.sol";
import { PositionManagerDependent } from "./PositionManagerDependent.sol";

contract PositionManagerWrappedCollateralToken is IPositionManagerWrappedCollateralToken, PositionManagerDependent {
    IERC20Wrapped public immutable override wrappedCollateralToken;

    IERC20 internal immutable _underlyingCollateralToken;

    IERC20Indexable internal immutable _raftDebtToken;

    IRToken internal immutable _rToken;

    constructor(
        address positionManager_,
        IERC20Wrapped wrappedCollateralToken_
    )
        PositionManagerDependent(positionManager_)
    {
        if (address(wrappedCollateralToken_) == address(0)) {
            revert WrappedCollateralTokenAddressCannotBeZero();
        }
        wrappedCollateralToken = wrappedCollateralToken_;
        _underlyingCollateralToken = wrappedCollateralToken_.underlying();

        _raftDebtToken = IPositionManager(positionManager_).raftDebtToken(wrappedCollateralToken);
        _rToken = IPositionManager(positionManager_).rToken();

        _underlyingCollateralToken.approve(address(wrappedCollateralToken), type(uint256).max);

        wrappedCollateralToken.approve(positionManager, type(uint256).max);
    }

    function managePosition(
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        ERC20PermitSignature calldata permitSignature
    )
        external
        override
    {
        ERC20PermitSignature memory emptySignature;

        if (!isDebtIncrease) {
            if (debtChange == type(uint256).max) {
                debtChange = _raftDebtToken.balanceOf(msg.sender);
            }
            _applyPermit(_rToken, permitSignature);
            _rToken.transferFrom(msg.sender, address(this), debtChange);
        }

        if (isCollateralIncrease && collateralChange > 0) {
            _underlyingCollateralToken.transferFrom(msg.sender, address(this), collateralChange);
            wrappedCollateralToken.depositFor(address(this), collateralChange);
        }

        (collateralChange, debtChange) = IPositionManager(positionManager).managePosition(
            wrappedCollateralToken,
            msg.sender,
            collateralChange,
            isCollateralIncrease,
            debtChange,
            isDebtIncrease,
            maxFeePercentage,
            emptySignature
        );

        if (!isCollateralIncrease && collateralChange > 0) {
            wrappedCollateralToken.withdrawTo(msg.sender, collateralChange);
        }

        if (isDebtIncrease) {
            _rToken.transfer(msg.sender, debtChange);
        }

        emit WrappedCollateralTokenPositionChanged(
            msg.sender, collateralChange, isCollateralIncrease, debtChange, isDebtIncrease
        );
    }

    function redeemCollateral(uint256 debtAmount, uint256 maxFeePercentage) external override {
        _rToken.transferFrom(msg.sender, address(this), debtAmount);

        IPositionManager(positionManager).redeemCollateral(wrappedCollateralToken, debtAmount, maxFeePercentage);

        wrappedCollateralToken.withdrawTo(msg.sender, wrappedCollateralToken.balanceOf(address(this)));
    }

    function _applyPermit(IERC20Permit token, ERC20PermitSignature calldata permitSignature) internal {
        if (address(permitSignature.token) == address(token)) {
            PermitHelper.applyPermit(permitSignature, msg.sender, address(this));
        }
    }
}
