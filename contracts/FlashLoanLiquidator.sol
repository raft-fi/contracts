// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import {
    IAaveV3FlashLoanSimpleReceiver,
    IPool,
    IPoolAddressesProvider
} from "./Dependencies/IAaveV3FlashLoanSimpleReceiver.sol";
import { ILiquidator } from "./Interfaces/ILiquidator.sol";
import { IPositionManager } from "./Interfaces/IPositionManager.sol";
import { IPriceFeed } from "./Interfaces/IPriceFeed.sol";
import { IRToken } from "./Interfaces/IRToken.sol";
import { PositionManagerDependent } from "./PositionManagerDependent.sol";
import { IAMM } from "./Interfaces/IAMM.sol";

contract FlashLoanLiquidator is ILiquidator, IAaveV3FlashLoanSimpleReceiver, PositionManagerDependent {
    using SafeERC20 for IERC20;

    IAMM public immutable amm;
    IERC20 public immutable collateralToken;
    IERC20 public immutable raftDebtToken;
    IRToken public immutable rToken;

    IPoolAddressesProvider public constant override ADDRESSES_PROVIDER =
        IPoolAddressesProvider(0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e);
    IPool public immutable override POOL;

    /// 113% - leave some buffer for fees
    uint256 private constant TARGET_CR = 1.13e18;

    /// @dev `executeOperation` was provided with an unexpected token.
    /// @param token The received token.
    error UnexpectedFlashLoanToken(address token);

    /// @dev `executeOperation` was called by an account other than the Aave Pool contract.
    error InvalidInvoker();

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

        rToken = positionManager_.rToken();
        raftDebtToken = positionManager_.raftDebtToken(collateralToken);
        POOL = IPool(ADDRESSES_PROVIDER.getPool());

        // We approve tokens here so we do not need to do approvals in particular actions.
        // Approved contracts are known, so this should be considered as safe.

        // No need to use safeApprove, IRToken is known token and is safe.
        rToken.approve(address(positionManager_.rToken()), type(uint256).max);
        collateralToken_.safeApprove(address(amm), type(uint256).max);
        collateralToken_.safeApprove(address(positionManager_), type(uint256).max);
    }

    function liquidate(address position, bytes calldata ammData) external {
        uint256 positionDebt = raftDebtToken.balanceOf(position);
        bytes memory data = abi.encode(msg.sender, position, positionDebt, ammData);

        uint256 flashLoanAmount = getRequiredCollateralForMintingGivenR(positionDebt);
        POOL.flashLoanSimple(address(this), address(collateralToken), flashLoanAmount, data, 0);
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes memory params
    )
        external
        override
        returns (bool)
    {
        if (asset != address(collateralToken)) {
            revert UnexpectedFlashLoanToken(asset);
        }
        if (msg.sender != address(POOL)) {
            revert InvalidInvoker();
        }
        if (initiator != address(this)) {
            revert InvalidInitiator();
        }

        (address liquidator, address position, uint256 positionDebt, bytes memory ammData) =
            abi.decode(params, (address, address, uint256, bytes));
        ERC20PermitSignature memory emptySignature;
        IPositionManager(positionManager).managePosition(
            collateralToken,
            address(this),
            amount,
            true,
            positionDebt,
            true,
            1e18, // maxFeePercentage can be 100% since the contract checks it made a profit anyway
            emptySignature
        );
        IPositionManager(positionManager).liquidate(position);

        uint256 swapAmount = collateralToken.balanceOf(address(this)) - premium;
        uint256 outstandingDebt = raftDebtToken.balanceOf(address(this));
        amm.swap(collateralToken, rToken, swapAmount, outstandingDebt, ammData);

        // close position
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

        // approve flash loan repayment
        collateralToken.safeApprove(address(POOL), amount + premium);

        /// send the remaining R to the liquidator
        rToken.transfer(liquidator, rToken.balanceOf(address(this)));

        return true;
    }

    function getRequiredCollateralForMintingGivenR(uint256 rAmount) internal returns (uint256) {
        (,, IPriceFeed priceFeed,,,,,,,) = IPositionManager(positionManager).collateralInfo(collateralToken);
        (uint256 price,) = priceFeed.fetchPrice();

        return rAmount * TARGET_CR / price;
    }
}
