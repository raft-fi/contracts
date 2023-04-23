// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IStETH } from "./Dependencies/IStETH.sol";
import { IWstETH } from "./Dependencies/IWstETH.sol";
import { IPositionManagerStETH } from "./Interfaces/IPositionManagerStETH.sol";
import { IPriceFeed } from "./Interfaces/IPriceFeed.sol";
import { ISplitLiquidationCollateral } from "./Interfaces/ISplitLiquidationCollateral.sol";
import { PositionManager } from "./PositionManager.sol";

contract PositionManagerStETH is IPositionManagerStETH, PositionManager {
    // --- Immutable variables ---

    IWstETH public immutable override wstETH;
    IStETH public immutable override stETH;

    // --- Constructor ---

    constructor(
        IPriceFeed priceFeed,
        IWstETH wstETH_,
        ISplitLiquidationCollateral newSplitLiquidationCollateral
    )
        PositionManager(newSplitLiquidationCollateral)
    {
        wstETH = wstETH_;
        stETH = IStETH(address(wstETH_.stETH()));

        addCollateralToken(wstETH_, priceFeed);
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
        uint256 wstETHBalanceBefore = wstETH.balanceOf(address(this));
        (bool sent,) = address(wstETH).call{ value: msg.value }("");
        if (!sent) {
            revert SendingEtherFailed();
        }
        uint256 wstETHBalanceAfter = wstETH.balanceOf(address(this));
        uint256 wstETHAmount = wstETHBalanceAfter - wstETHBalanceBefore;

        _managePosition(wstETH, msg.sender, wstETHAmount, true, debtChange, isDebtIncrease, maxFeePercentage, false);
    }

    function managePositionETH(
        address borrower,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage
    )
        external
        payable
        override
    {
        uint256 wstETHBalanceBefore = wstETH.balanceOf(address(this));
        (bool sent,) = address(wstETH).call{ value: msg.value }("");
        if (!sent) {
            revert SendingEtherFailed();
        }
        uint256 wstETHBalanceAfter = wstETH.balanceOf(address(this));
        uint256 wstETHAmount = wstETHBalanceAfter - wstETHBalanceBefore;

        _managePosition(wstETH, borrower, wstETHAmount, true, debtChange, isDebtIncrease, maxFeePercentage, false);
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
        if (isCollateralIncrease) {
            stETH.transferFrom(msg.sender, address(this), collateralChange);
            stETH.approve(address(wstETH), collateralChange);
            uint256 wstETHAmount = wstETH.wrap(collateralChange);
            _managePosition(
                wstETH,
                msg.sender,
                wstETHAmount,
                isCollateralIncrease,
                debtChange,
                isDebtIncrease,
                maxFeePercentage,
                false
            );
        } else {
            _managePosition(
                wstETH,
                msg.sender,
                collateralChange,
                isCollateralIncrease,
                debtChange,
                isDebtIncrease,
                maxFeePercentage,
                false
            );
            uint256 stETHAmount = wstETH.unwrap(collateralChange);
            stETH.transfer(msg.sender, stETHAmount);
        }
    }

    function managePositionStETH(
        address borrower,
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage
    )
        external
        override
    {
        if (isCollateralIncrease) {
            stETH.transferFrom(msg.sender, address(this), collateralChange);
            stETH.approve(address(wstETH), collateralChange);
            uint256 wstETHAmount = wstETH.wrap(collateralChange);
            _managePosition(
                wstETH,
                borrower,
                wstETHAmount,
                isCollateralIncrease,
                debtChange,
                isDebtIncrease,
                maxFeePercentage,
                false
            );
        } else {
            _managePosition(
                wstETH,
                borrower,
                collateralChange,
                isCollateralIncrease,
                debtChange,
                isDebtIncrease,
                maxFeePercentage,
                false
            );
            uint256 stETHAmount = wstETH.unwrap(collateralChange);
            stETH.transfer(msg.sender, stETHAmount);
        }
    }
}
