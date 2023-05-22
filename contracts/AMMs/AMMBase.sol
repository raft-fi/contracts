// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAMM } from "../Interfaces/IAMM.sol";

abstract contract AMMBase is IAMM {
    using SafeERC20 for IERC20;

    function swap(
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn,
        uint256 minReturn,
        bytes calldata extraData
    )
        external
        override
        returns (uint256 amountOut)
    {
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 balanceBeforeTokenIn = tokenIn.balanceOf(address(this));
        uint256 balanceBeforeTokenOut = tokenOut.balanceOf(address(this));

        _executeSwap(tokenIn, amountIn, minReturn, extraData);

        /// Here we allow a 1 wei error in the tokenIn amount pulled from address(this) to accommodate
        /// for rounding errors in rebasing tokens such as stETH.
        uint256 balanceAfterTokenIn = tokenIn.balanceOf(address(this));
        uint256 expectedBalanceAfterTokenIn = balanceBeforeTokenIn - amountIn;
        uint256 tokenInDelta = balanceAfterTokenIn > expectedBalanceAfterTokenIn
            ? balanceAfterTokenIn - expectedBalanceAfterTokenIn
            : expectedBalanceAfterTokenIn - balanceAfterTokenIn;
        if (tokenInDelta > 1) {
            revert SwapPartiallyFilled();
        }

        amountOut = tokenOut.balanceOf(address(this)) - balanceBeforeTokenOut;
        if (amountOut < minReturn) {
            revert InsufficientAmountReceived(amountOut, minReturn);
        }

        emit Swap(address(tokenIn), address(tokenOut), amountIn, amountOut, minReturn);

        tokenOut.safeTransfer(msg.sender, amountOut);
    }

    function _executeSwap(
        IERC20 tokenIn,
        uint256 amountIn,
        uint256 minReturn,
        bytes calldata extraData
    )
        internal
        virtual;
}
