// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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
        uint256 wstETHAmount = wrapETH();
        IPositionManager(positionManager).managePosition(
            wstETH, msg.sender, wstETHAmount, true, debtChange, isDebtIncrease, maxFeePercentage
        );
    }

    function managePositionStETH(
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage
    )
        external
        override
    {
        if (isCollateralIncrease && collateralChange > 0) {
            uint256 wstETHAmount = wrapStETH(collateralChange);
            IPositionManager(positionManager).managePosition(
                wstETH, msg.sender, wstETHAmount, isCollateralIncrease, debtChange, isDebtIncrease, maxFeePercentage
            );
        } else {
            IPositionManager(positionManager).managePosition(
                wstETH,
                msg.sender,
                collateralChange,
                isCollateralIncrease,
                debtChange,
                isDebtIncrease,
                maxFeePercentage
            );
            uint256 stETHAmount = unwrapStETH(collateralChange);
            stETH.transfer(msg.sender, stETHAmount);
        }
    }
}
