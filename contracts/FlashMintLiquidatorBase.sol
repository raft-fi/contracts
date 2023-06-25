// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC3156FlashBorrower } from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ILiquidator } from "./Interfaces/ILiquidator.sol";
import { IPositionManager } from "./Interfaces/IPositionManager.sol";
import { IRToken } from "./Interfaces/IRToken.sol";
import { PositionManagerDependent } from "./PositionManagerDependent.sol";
import { IAMM } from "./Interfaces/IAMM.sol";

abstract contract FlashMintLiquidatorBase is ILiquidator, IERC3156FlashBorrower, PositionManagerDependent {
    using SafeERC20 for IERC20;

    IAMM public immutable override amm;
    IERC20 public immutable override collateralToken;
    IERC20 public immutable override collateralUnderlyingToken;
    IERC20 public immutable override raftDebtToken;
    IRToken public immutable override rToken;

    constructor(
        IPositionManager positionManager_,
        IAMM amm_,
        IERC20 collateralToken_,
        IERC20 collateralUnderlyingToken_
    )
        PositionManagerDependent(address(positionManager_))
    {
        if (address(amm_) == address(0)) {
            revert AmmCannotBeZero();
        }
        if (address(collateralToken_) == address(0)) {
            revert CollateralTokenCannotBeZero();
        }
        if (address(collateralUnderlyingToken_) == address(0)) {
            revert CollateralTokenCannotBeZero();
        }
        amm = amm_;
        collateralToken = collateralToken_;
        collateralUnderlyingToken = collateralUnderlyingToken_;

        rToken = positionManager_.rToken();
        raftDebtToken = positionManager_.raftDebtToken(collateralToken);

        // We approve tokens here so we do not need to do approvals in particular actions.
        // Approved contracts are known, so this should be considered as safe.
        // No need to use safeApprove, IRToken is known token and is safe.
        rToken.approve(address(rToken), type(uint256).max);
        collateralUnderlyingToken.safeApprove(address(amm), type(uint256).max);
    }

    function liquidate(address position, bytes calldata ammData) external override {
        bytes memory data = abi.encode(msg.sender, position, ammData);
        rToken.flashLoan(this, address(rToken), raftDebtToken.balanceOf(position), data);
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
        if (msg.sender != address(rToken)) {
            revert UnsupportedToken();
        }
        if (initiator != address(this)) {
            revert InvalidInitiator();
        }

        (address liquidator, address position, bytes memory ammData) = abi.decode(data, (address, address, bytes));

        IPositionManager(positionManager).liquidate(position);
        uint256 swapAmount = collateralToken.balanceOf(address(this));
        uint256 repayAmount = amount + fee;
        _beforeSwap(swapAmount);
        amm.swap(collateralUnderlyingToken, rToken, swapAmount, repayAmount, ammData);
        rToken.transfer(liquidator, rToken.balanceOf(address(this)) - repayAmount);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    // solhint-disable-next-line no-empty-blocks
    function _beforeSwap(uint256 swapAmount) internal virtual { }
}
