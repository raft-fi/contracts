// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC3156FlashBorrower } from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import { IWstETH } from "./Dependencies/IWstETH.sol";
import { IPositionManager } from "./Interfaces/IPositionManager.sol";
import { IOneStepLeverageStETH } from "./Interfaces/IOneStepLeverageStETH.sol";
import { OneStepLeverage } from "./OneStepLeverage.sol";
import { WstETHWrapper } from "./WstETHWrapper.sol";
import { IAMM } from "./Interfaces/IAMM.sol";

contract OneStepLeverageStETH is IERC3156FlashBorrower, IOneStepLeverageStETH, WstETHWrapper, OneStepLeverage {
    constructor(
        IPositionManager positionManager_,
        IAMM amm_,
        IWstETH wstETH_
    )
        OneStepLeverage(positionManager_, amm_, wstETH_)
        WstETHWrapper(wstETH_)
    { }

    function manageLeveragedPositionStETH(
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 stETHCollateralChange,
        bool stETHCollateralIncrease,
        bytes calldata ammData,
        uint256 minReturnOrAmountToSell,
        uint256 maxFeePercentage
    )
        external
        override
    {
        uint256 wstETHCollateralChange = (stETHCollateralIncrease && stETHCollateralChange > 0)
            ? wrapStETH(stETHCollateralChange)
            : wstETH.getWstETHByStETH(stETHCollateralChange);

        wstETHCollateralChange = _manageLeveragedPosition(
            debtChange,
            isDebtIncrease,
            wstETHCollateralChange,
            stETHCollateralIncrease,
            ammData,
            minReturnOrAmountToSell,
            maxFeePercentage,
            false
        );

        if (!stETHCollateralIncrease && wstETHCollateralChange > 0) {
            unwrapStETH(wstETHCollateralChange);
        }
    }

    function manageLeveragedPositionETH(
        uint256 debtChange,
        bool isDebtIncrease,
        bytes calldata ammData,
        uint256 minReturnOrAmountToSell,
        uint256 maxFeePercentage
    )
        external
        payable
        override
    {
        uint256 principalCollateralChange = wrapETH();
        if (principalCollateralChange == 0) {
            revert NoETHProvided();
        }

        _manageLeveragedPosition(
            debtChange,
            isDebtIncrease,
            principalCollateralChange,
            true,
            ammData,
            minReturnOrAmountToSell,
            maxFeePercentage,
            true
        );
    }
}
