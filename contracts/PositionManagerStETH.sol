// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IStETH } from "./Dependencies/IStETH.sol";
import { IWstETH } from "./Dependencies/IWstETH.sol";
import { IPositionManager } from "./Interfaces/IPositionManager.sol";
import { IPositionManagerStETH } from "./Interfaces/IPositionManagerStETH.sol";
import { ISplitLiquidationCollateral } from "./Interfaces/ISplitLiquidationCollateral.sol";
import { PositionManagerDependent } from "./PositionManagerDependent.sol";

contract PositionManagerStETH is IPositionManagerStETH, PositionManagerDependent {
    // --- Immutable variables ---

    IWstETH public immutable override wstETH;
    IStETH public immutable override stETH;

    // --- Constructor ---

    constructor(address positionManager_, IWstETH wstETH_) PositionManagerDependent(positionManager_) {
        if (address(wstETH_) == address(0)) {
            revert WstETHAddressCannotBeZero();
        }

        wstETH = wstETH_;
        stETH = IStETH(address(wstETH_.stETH()));

        stETH.approve(address(wstETH), type(uint256).max); // for wrapping
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
        uint256 wstETHBalanceBefore = wstETH.balanceOf(address(this));
        (bool sent,) = address(wstETH).call{ value: msg.value }("");
        if (!sent) {
            revert SendingEtherFailed();
        }
        uint256 wstETHBalanceAfter = wstETH.balanceOf(address(this));
        uint256 wstETHAmount = wstETHBalanceAfter - wstETHBalanceBefore;

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
        if (isCollateralIncrease) {
            stETH.transferFrom(msg.sender, address(this), collateralChange);
            uint256 wstETHAmount = wstETH.wrap(collateralChange);
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
            uint256 stETHAmount = wstETH.unwrap(collateralChange);
            stETH.transfer(msg.sender, stETHAmount);
        }
    }
}
