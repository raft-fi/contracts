// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IPositionManager } from "./Interfaces/IPositionManager.sol";
import { IPositionManagerWrappedCollateralToken } from "./Interfaces/IPositionManagerWrappedCollateralToken.sol";
import { IAMM } from "./Interfaces/IAMM.sol";
import { IRToken } from "./Interfaces/IRToken.sol";
import { IERC20Wrapped } from "./Interfaces/IERC20Wrapped.sol";
import { FlashLoanLiquidatorBase } from "./FlashLoanLiquidatorBase.sol";

contract FlashLoanLiquidatorWrappedCollateral is FlashLoanLiquidatorBase {
    using SafeERC20 for IERC20;
    using SafeERC20 for IRToken;

    IPositionManagerWrappedCollateralToken public immutable positionManagerWrappedCollateral;

    constructor(
        IPositionManagerWrappedCollateralToken positionManagerWrappedCollateral_,
        IAMM amm_
    )
        FlashLoanLiquidatorBase(
            IPositionManager(positionManagerWrappedCollateral_.positionManager()),
            amm_,
            positionManagerWrappedCollateral_.wrappedCollateralToken(),
            positionManagerWrappedCollateral_.wrappedCollateralToken().underlying()
        )
    {
        positionManagerWrappedCollateral = positionManagerWrappedCollateral_;

        IPositionManager(positionManager).rToken().safeApprove(
            address(positionManagerWrappedCollateral_), type(uint256).max
        );
        collateralUnderlyingToken.safeApprove(address(positionManagerWrappedCollateral_), type(uint256).max);

        IPositionManager(positionManager).whitelistDelegate(address(positionManagerWrappedCollateral_), true);
    }

    function _beforeSwap(uint256 swapAmount) internal override {
        IERC20Wrapped(address(collateralToken)).withdrawTo(address(this), swapAmount);
    }

    function _openPosition(uint256 depositAmount, uint256 positionDebt) internal override {
        ERC20PermitSignature memory emptySignature;
        positionManagerWrappedCollateral.managePosition(
            depositAmount,
            true,
            positionDebt,
            true,
            1e18, // maxFeePercentage can be 100% since returning the flash loan will fail if no profit was made
            emptySignature
        );
    }

    function _closePosition(uint256 outstandingDebt) internal override {
        ERC20PermitSignature memory emptySignature;
        positionManagerWrappedCollateral.managePosition(
            0,
            /// 0 because we're doing full repayment
            false,
            outstandingDebt,
            false,
            0, // irrelevant since we are closing the position
            emptySignature
        );

        IERC20Wrapped(address(collateralToken)).withdrawTo(
            address(this), IERC20Wrapped(address(collateralToken)).balanceOf(address(this))
        );
    }
}
