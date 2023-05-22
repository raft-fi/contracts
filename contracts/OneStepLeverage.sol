// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC3156FlashBorrower } from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IPositionManager } from "./Interfaces/IPositionManager.sol";
import { IRToken } from "./Interfaces/IRToken.sol";
import { PositionManagerDependent } from "./PositionManagerDependent.sol";
import { IOneStepLeverage } from "./Interfaces/IOneStepLeverage.sol";
import { IAMM } from "./Interfaces/IAMM.sol";
import { IERC20Indexable } from "./Interfaces/IERC20Indexable.sol";

contract OneStepLeverage is IOneStepLeverage, PositionManagerDependent {
    using SafeERC20 for IERC20;

    IAMM public immutable override amm;
    IERC20 public immutable override collateralToken;
    IERC20Indexable public immutable override raftDebtToken;
    IERC20Indexable public immutable override raftCollateralToken;

    uint256 public constant override MAX_LEFTOVER_R = 1e18;

    constructor(
        IPositionManager positionManager_,
        IAMM amm_,
        IERC20 collateralToken_
    )
        PositionManagerDependent(address(positionManager_))
    {
        if (address(amm_) == address(0)) {
            revert AmmCannotBeZero();
        }
        if (address(collateralToken_) == address(0)) {
            revert CollateralTokenCannotBeZero();
        }
        amm = amm_;
        collateralToken = collateralToken_;
        raftCollateralToken = positionManager_.raftCollateralToken(collateralToken);
        raftDebtToken = positionManager_.raftDebtToken(collateralToken);

        // We approve tokens here so we do not need to do approvals in particular actions.
        // Approved contracts are known, so this should be considered as safe.

        // No need to use safeApprove, IRToken is known token and is safe.
        positionManager_.rToken().approve(address(amm), type(uint256).max);
        positionManager_.rToken().approve(address(positionManager_.rToken()), type(uint256).max);
        collateralToken_.safeApprove(address(amm), type(uint256).max);
        collateralToken_.safeApprove(address(positionManager_), type(uint256).max);
    }

    function manageLeveragedPosition(
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 principalCollateralChange,
        bool principalCollateralIncrease,
        bytes calldata ammData,
        uint256 minReturnOrAmountToSell,
        uint256 maxFeePercentage
    )
        external
        override
    {
        if (principalCollateralIncrease && principalCollateralChange > 0) {
            collateralToken.safeTransferFrom(msg.sender, address(this), principalCollateralChange);
        }

        _manageLeveragedPosition(
            debtChange,
            isDebtIncrease,
            principalCollateralChange,
            principalCollateralIncrease,
            ammData,
            minReturnOrAmountToSell,
            maxFeePercentage,
            true
        );
    }

    function _manageLeveragedPosition(
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 principalCollateralChange,
        bool principalCollateralIncrease,
        bytes calldata ammData,
        uint256 minReturnOrAmountToSell,
        uint256 maxFeePercentage,
        bool releasePrincipals
    )
        internal
        returns (uint256 actualCollateralChange)
    {
        if (debtChange == 0) {
            revert ZeroDebtChange();
        }

        bool fullRepayment;
        if (!isDebtIncrease) {
            uint256 positionDebt = raftDebtToken.balanceOf(msg.sender);
            if (debtChange == type(uint256).max) {
                debtChange = positionDebt;
            }
            fullRepayment = (debtChange == positionDebt);

            actualCollateralChange =
                fullRepayment ? raftCollateralToken.balanceOf(msg.sender) : principalCollateralChange;
        } else {
            actualCollateralChange = principalCollateralChange;
        }

        bytes memory data = abi.encode(
            msg.sender,
            principalCollateralChange,
            principalCollateralIncrease,
            isDebtIncrease,
            ammData,
            minReturnOrAmountToSell,
            maxFeePercentage,
            releasePrincipals,
            fullRepayment,
            actualCollateralChange
        );

        IRToken rToken = IPositionManager(positionManager).rToken();
        rToken.flashLoan(this, address(rToken), debtChange, data);
    }

    function onFlashLoan(
        address initiator,
        address,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    )
        external
        override
        returns (bytes32)
    {
        IERC20 rToken = IPositionManager(positionManager).rToken();
        if (msg.sender != address(rToken)) {
            revert UnsupportedToken();
        }
        if (initiator != address(this)) {
            revert InvalidInitiator();
        }

        (
            address user,
            uint256 principalCollateralChange,
            bool principalCollateralIncrease,
            bool isDebtIncrease,
            bytes memory ammData,
            uint256 minReturnOrAmountToSell,
            uint256 maxFeePercentage,
            bool releasePrincipals,
            bool fullRepayment,
            uint256 actualCollateralChange
        ) = abi.decode(data, (address, uint256, bool, bool, bytes, uint256, uint256, bool, bool, uint256));

        uint256 leveragedCollateralChange = isDebtIncrease
            ? amm.swap(rToken, collateralToken, amount, minReturnOrAmountToSell, ammData)
            : minReturnOrAmountToSell;

        uint256 collateralChange;
        bool increaseCollateral;
        if (principalCollateralIncrease != isDebtIncrease) {
            collateralChange = principalCollateralChange > leveragedCollateralChange
                ? principalCollateralChange - leveragedCollateralChange
                : leveragedCollateralChange - principalCollateralChange;

            increaseCollateral = principalCollateralIncrease && !isDebtIncrease
                ? principalCollateralChange > leveragedCollateralChange
                : leveragedCollateralChange > principalCollateralChange;
        } else {
            increaseCollateral = principalCollateralIncrease;
            collateralChange = principalCollateralChange + (fullRepayment ? 0 : leveragedCollateralChange);
        }

        ERC20PermitSignature memory emptySignature;
        IPositionManager(positionManager).managePosition(
            collateralToken,
            user,
            collateralChange,
            increaseCollateral,
            amount + (isDebtIncrease ? fee : 0),
            isDebtIncrease,
            maxFeePercentage,
            emptySignature
        );

        if (releasePrincipals && !principalCollateralIncrease && actualCollateralChange > 0) {
            collateralToken.safeTransfer(user, actualCollateralChange - (fullRepayment ? minReturnOrAmountToSell : 0));
        }
        if (!isDebtIncrease) {
            uint256 repayAmount = amount + fee;
            uint256 amountOut = amm.swap(collateralToken, rToken, leveragedCollateralChange, repayAmount, ammData);
            if (amountOut > repayAmount + MAX_LEFTOVER_R) {
                // No need to use safeTransfer as rToken is known
                rToken.transfer(user, amountOut - repayAmount);
            }
        }

        emit LeveragedPositionAdjusted(
            user,
            principalCollateralChange,
            principalCollateralIncrease,
            amount,
            isDebtIncrease,
            leveragedCollateralChange
        );
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
