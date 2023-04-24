// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAMM } from "../../contracts/Interfaces/IAMM.sol";

/* Tester contract for math functions in Math.sol library. */

error BelowMinReturn();

contract MockAMM is IAMM {
    IERC20 public immutable token1;
    IERC20 public immutable token2;
    uint256 public token1Rate; // expressed in token2

    constructor(IERC20 token1_, IERC20 token2_, uint256 token1Rate_) {
        token1 = token1_;
        token2 = token2_;
        token1Rate = token1Rate_;
    }

    function setRate(uint256 token1Rate_) external {
        token1Rate = token1Rate_;
    }

    function getAmountOut(
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn,
        bytes calldata
    )
        private
        view
        returns (uint256 amountOut)
    {
        uint256 rate = _getRate(tokenIn, tokenOut);
        return amountIn * rate / 1e18;
    }

    function swap(
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn,
        uint256 minReturn,
        bytes calldata extraData
    )
        external
        override
        returns (uint256 amountReceived)
    {
        tokenIn.transferFrom(msg.sender, address(this), amountIn);
        amountReceived = getAmountOut(tokenIn, tokenOut, amountIn, extraData);
        if (amountReceived < minReturn) {
            revert BelowMinReturn();
        }
        tokenOut.transfer(msg.sender, amountReceived);
    }

    function _getRate(IERC20 tokenIn, IERC20 tokenOut) internal view returns (uint256) {
        if (tokenIn == token1 && tokenOut == token2) {
            return token1Rate;
        } else if (tokenIn == token2 && tokenOut == token1) {
            return 1e18 * 1e18 / token1Rate;
        }
        revert("invalid tokens provided");
    }
}
