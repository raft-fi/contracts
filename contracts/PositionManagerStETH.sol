// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IWstETH } from "./Dependencies/IWstETH.sol";
import { IERC20Wrapped } from "./Interfaces/IERC20Wrapped.sol";
import { IWrappedCollateralToken } from "./Interfaces/IWrappedCollateralToken.sol";
import { IPositionManager } from "./Interfaces/IPositionManager.sol";
import { IPositionManagerStETH } from "./Interfaces/IPositionManagerStETH.sol";
import { PositionManagerWrappedCollateralToken } from "./PositionManagerWrappedCollateralToken.sol";
import { WstETHWrapper } from "./WstETHWrapper.sol";

contract PositionManagerStETH is IPositionManagerStETH, PositionManagerWrappedCollateralToken, WstETHWrapper {
    // --- Constructor ---

    /* solhint-disable no-empty-blocks */
    constructor(
        address positionManager_,
        IERC20Wrapped wrappedCollateralToken_
    )
        PositionManagerWrappedCollateralToken(positionManager_, wrappedCollateralToken_)
        WstETHWrapper(IWstETH(address(wrappedCollateralToken_.underlying())))
    { }
    /* solhint-enable no-empty-blocks */

    // --- Functions ---

    function managePositionStETH(
        uint256 stETHCollateralChange,
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

        uint256 wstETHCollateralChange;
        if (isCollateralIncrease && stETHCollateralChange > 0) {
            wstETHCollateralChange = wrapStETH(stETHCollateralChange);
            IWrappedCollateralToken(address(wrappedCollateralToken)).depositForWithAccountCheck(
                address(this), msg.sender, wstETHCollateralChange
            );
        } else {
            wstETHCollateralChange = wstETH.getWstETHByStETH(stETHCollateralChange);
        }

        (wstETHCollateralChange, debtChange) = IPositionManager(positionManager).managePosition(
            wrappedCollateralToken,
            msg.sender,
            wstETHCollateralChange,
            isCollateralIncrease,
            debtChange,
            isDebtIncrease,
            maxFeePercentage,
            emptySignature
        );

        if (!isCollateralIncrease && wstETHCollateralChange > 0) {
            wrappedCollateralToken.withdrawTo(address(this), wstETHCollateralChange);
            unwrapStETH(wstETHCollateralChange);
        }

        if (isDebtIncrease) {
            _rToken.transfer(msg.sender, debtChange);
        }

        emit StETHPositionChanged(msg.sender, stETHCollateralChange, isCollateralIncrease, debtChange, isDebtIncrease);
    }
}
