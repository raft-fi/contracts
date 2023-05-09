// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IWstETH } from "./Dependencies/IWstETH.sol";
import { IPositionManager } from "./Interfaces/IPositionManager.sol";
import { IPositionManagerStETH } from "./Interfaces/IPositionManagerStETH.sol";
import { PositionManagerDependent } from "./PositionManagerDependent.sol";
import { WstETHWrapper } from "./WstETHWrapper.sol";

contract PositionManagerStETH is IPositionManagerStETH, PositionManagerDependent, WstETHWrapper {
    // --- Constructor ---
    constructor(
        address positionManager_,
        IWstETH wstETH_
    )
        PositionManagerDependent(positionManager_)
        WstETHWrapper(wstETH_)
    {
        wstETH.approve(positionManager, type(uint256).max); // for deposits
    }

    // --- Functions ---

    function managePositionETH(
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage
    )
        external
        payable
        override
    {
        ERC20PermitSignature memory emptySignature;
        uint256 wstETHAmount = wrapETH();
        if (!isDebtIncrease) {
            IPositionManager(positionManager).rToken().transferFrom(msg.sender, address(this), debtChange);
        }
        IPositionManager(positionManager).managePosition(
            wstETH, msg.sender, wstETHAmount, true, debtChange, isDebtIncrease, maxFeePercentage, emptySignature
        );
        if (isDebtIncrease) {
            IPositionManager(positionManager).rToken().transfer(msg.sender, debtChange);
        }
    }

    function managePositionStETH(
        uint256 stETHCollateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage
    )
        external
        override
    {
        ERC20PermitSignature memory emptySignature;
        if (!isDebtIncrease) {
            IPositionManager(positionManager).rToken().transferFrom(msg.sender, address(this), debtChange);
        }
        uint256 wstETHCollateralChange = (isCollateralIncrease && stETHCollateralChange > 0)
            ? wrapStETH(stETHCollateralChange)
            : wstETH.getWstETHByStETH(stETHCollateralChange);

        IPositionManager(positionManager).managePosition(
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
            IPositionManager(positionManager).rToken().transfer(msg.sender, debtChange);
        }
    }
}
