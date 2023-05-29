// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import { ERC20PermitSignature, PermitHelper } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IWstETH } from "./Dependencies/IWstETH.sol";
import { IERC20Indexable } from "./Interfaces/IERC20Indexable.sol";
import { IPositionManager } from "./Interfaces/IPositionManager.sol";
import { IPositionManagerStETH } from "./Interfaces/IPositionManagerStETH.sol";
import { IRToken } from "./Interfaces/IRToken.sol";
import { PositionManagerDependent } from "./PositionManagerDependent.sol";
import { WstETHWrapper } from "./WstETHWrapper.sol";

contract PositionManagerStETH is IPositionManagerStETH, PositionManagerDependent, WstETHWrapper {
    IERC20Indexable private immutable raftDebtToken;
    IRToken private immutable rToken;

    // --- Constructor ---

    constructor(
        address positionManager_,
        IWstETH wstETH_
    )
        PositionManagerDependent(positionManager_)
        WstETHWrapper(wstETH_)
    {
        (, raftDebtToken,,,,,,,,) = IPositionManager(positionManager_).collateralInfo(wstETH);
        rToken = IPositionManager(positionManager_).rToken();
        wstETH.approve(positionManager, type(uint256).max); // for deposits
    }

    // --- Functions ---

    function managePositionETH(
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        ERC20PermitSignature calldata permitSignature
    )
        external
        payable
        override
    {
        ERC20PermitSignature memory emptySignature;
        uint256 wstETHAmount = wrapETH();

        if (!isDebtIncrease) {
            _applyPermit(rToken, permitSignature);
            rToken.transferFrom(msg.sender, address(this), debtChange);
        }

        IPositionManager(positionManager).managePosition(
            wstETH, msg.sender, wstETHAmount, true, debtChange, isDebtIncrease, maxFeePercentage, emptySignature
        );
        if (isDebtIncrease) {
            rToken.transfer(msg.sender, debtChange);
        }

        emit ETHPositionChanged(msg.sender, msg.value, debtChange, isDebtIncrease);
    }

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
                debtChange = raftDebtToken.balanceOf(msg.sender);
            }
            _applyPermit(rToken, permitSignature);
            rToken.transferFrom(msg.sender, address(this), debtChange);
        }

        uint256 wstETHCollateralChange = (isCollateralIncrease && stETHCollateralChange > 0)
            ? wrapStETH(stETHCollateralChange)
            : wstETH.getWstETHByStETH(stETHCollateralChange);

        (wstETHCollateralChange, debtChange) = IPositionManager(positionManager).managePosition(
            wstETH,
            msg.sender,
            wstETHCollateralChange,
            isCollateralIncrease,
            debtChange,
            isDebtIncrease,
            maxFeePercentage,
            emptySignature
        );

        if (!isCollateralIncrease && wstETHCollateralChange > 0) {
            unwrapStETH(wstETHCollateralChange);
        }

        if (isDebtIncrease) {
            rToken.transfer(msg.sender, debtChange);
        }

        emit StETHPositionChanged(msg.sender, stETHCollateralChange, isCollateralIncrease, debtChange, isDebtIncrease);
    }

    function _applyPermit(IERC20Permit token, ERC20PermitSignature calldata permitSignature) internal {
        if (address(permitSignature.token) == address(token)) {
            PermitHelper.applyPermit(permitSignature, msg.sender, address(this));
        }
    }
}
