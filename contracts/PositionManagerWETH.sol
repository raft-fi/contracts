// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IERC20Wrapped } from "./Interfaces/IERC20Wrapped.sol";
import { IWrappedCollateralToken } from "./Interfaces/IWrappedCollateralToken.sol";
import { IPositionManager } from "./Interfaces/IPositionManager.sol";
import { IWETH, IPositionManagerWETH } from "./Interfaces/IPositionManagerWETH.sol";
import { PositionManagerWrappedCollateralToken } from "./PositionManagerWrappedCollateralToken.sol";

contract PositionManagerWETH is IPositionManagerWETH, PositionManagerWrappedCollateralToken {
    // --- Constructor ---

    /* solhint-disable no-empty-blocks */
    constructor(
        address positionManager_,
        IERC20Wrapped wrappedCollateralToken_
    )
        PositionManagerWrappedCollateralToken(positionManager_, wrappedCollateralToken_)
    { }
    /* solhint-enable no-empty-blocks */

    // --- Functions ---

    function managePositionETH(
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        ERC20PermitSignature calldata permitSignature
    )
        external
        payable
        override
    {
        if (!isCollateralIncrease && msg.value > 0) {
            revert CannotSendETHWhenCollateralDecrease();
        }

        ERC20PermitSignature memory emptySignature;

        if (!isDebtIncrease) {
            if (debtChange == type(uint256).max) {
                debtChange = _raftDebtToken.balanceOf(msg.sender);
            }
            _applyPermit(_rToken, permitSignature);
            _rToken.transferFrom(msg.sender, address(this), debtChange);
        }

        if (isCollateralIncrease) {
            if (collateralChange != msg.value) {
                revert CollateralChangeAmountDoesNotMatchETHValue();
            }
            IWETH(address(_underlyingCollateralToken)).deposit{ value: msg.value }();
            IWrappedCollateralToken(address(wrappedCollateralToken)).depositForWithAccountCheck(
                address(this), msg.sender, msg.value
            );
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

        if (isDebtIncrease) {
            _rToken.transfer(msg.sender, debtChange);
        }

        if (!isCollateralIncrease && collateralChange > 0) {
            wrappedCollateralToken.withdrawTo(address(this), collateralChange);
            IWETH(address(_underlyingCollateralToken)).withdraw(collateralChange);
            (bool success,) = msg.sender.call{ value: collateralChange }("");
            if (!success) {
                revert SendingEtherFailed();
            }
        }

        emit ETHPositionChanged(msg.sender, collateralChange, isCollateralIncrease, debtChange, isDebtIncrease);
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable { }
}
