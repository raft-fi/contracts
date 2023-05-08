// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Interface that particular AMM integrations need to implement in order to be used in OneStepLeverage.
/// Implementation will be used to swap between R and collateralToken.
interface IAMM {
    /// @dev Thrown when the amount received after a swap is below the provided minimum return parameter.
    /// @param amountReceived The amount of tokens received after the swap.
    /// @param minReturn The provided minimum return.
    error InsufficientAmountReceived(uint256 amountReceived, uint256 minReturn);

    /// @dev Thrown when a swap is only partially filled.
    error SwapPartiallyFilled();

    /// @dev Emitted when a swap between two tokens occurs.
    /// @param tokenIn The address of the input token being swapped.
    /// @param tokenOut The address of the output token being swapped.
    /// @param amountIn The amount of input tokens being swapped.
    /// @param amountOut The amount of output tokens being swapped.
    /// @param minReturn The minimum acceptable return for the swap (expressed in `tokenOut`).
    event Swap(
        address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut, uint256 minReturn
    );

    /// @dev Swaps `amountIn` of `tokenIn` for `tokenOut`. Fails if returned amount is smaller than `minReturn`.
    /// @param tokenIn Address of the token that is being swapped.
    /// @param tokenOut Address of the token to swap for.
    /// @param amountIn Amount of `tokenIn` being swapped.
    /// @param minReturn Minimum amount of `tokenOut` to get as a result of swap.
    /// @param extraData Extra data for particular integration with DEX/Aggregator.
    /// @return amountOut Actual amount that was returned from swap. Needs to be >= `minReturn`.
    function swap(
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn,
        uint256 minReturn,
        bytes calldata extraData
    )
        external
        returns (uint256 amountOut);
}
