// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IPositionManager } from "./Interfaces/IPositionManager.sol";
import { IAMM } from "./Interfaces/IAMM.sol";
import { FlashLoanLiquidatorBase } from "./FlashLoanLiquidatorBase.sol";

contract FlashLoanLiquidator is FlashLoanLiquidatorBase {
    using SafeERC20 for IERC20;

    constructor(
        IPositionManager positionManager_,
        IAMM amm_,
        IERC20 collateralToken_
    )
        FlashLoanLiquidatorBase(positionManager_, amm_, collateralToken_, collateralToken_)
    {
        collateralToken.safeApprove(address(positionManager_), type(uint256).max);
    }

    function _openPosition(uint256 depositAmount, uint256 positionDebt) internal override {
        ERC20PermitSignature memory emptySignature;
        IPositionManager(positionManager).managePosition(
            collateralToken,
            address(this),
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
        IPositionManager(positionManager).managePosition(
            collateralToken,
            address(this),
            0,
            /// 0 because we're doing full repayment
            false,
            outstandingDebt,
            false,
            0, // irrelevant since we are closing the position
            emptySignature
        );
    }
}
