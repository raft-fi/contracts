// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAMM } from "../Interfaces/IAMM.sol";
import { IParaSwapAugustus } from "../Dependencies/IParaSwapAugustus.sol";
import { IParaSwapAugustusRegistry } from "../Dependencies/IParaSwapAugustusRegistry.sol";

contract ParaSwapAMM is IAMM {
    using SafeERC20 for IERC20;

    IParaSwapAugustusRegistry public immutable augustusRegistry;

    /// @dev Thrown when the amount received after a swap is below the provided minimum return parameter.
    /// @param amountReceived The amount of tokens received after the swap.
    /// @param minReturn The provided minimum return.
    error InsufficientAmountReceived(uint256 amountReceived, uint256 minReturn);

    /// @dev Thrown when a swap is only partially filled.
    error SwapPartiallyFilled();

    /// @dev Thrown when an invalid Augustus contract is provided.
    error InvalidAugustusContract();

    /// @dev Thrown when `swap` is provided with an invalid fromAmountOffset parameter.
    /// @param fromAmountOffset The invalid value that was provided.
    error FromAmountOffsetOutOfRange(uint256 fromAmountOffset);

    /// @dev Thrown when provided with a zero address Augustus Registry constructor argument.
    error ZeroAddressAugustusRegistry();

    constructor(address _augustusRegistry) {
        if (_augustusRegistry == address(0)) {
            revert ZeroAddressAugustusRegistry();
        }
        augustusRegistry = IParaSwapAugustusRegistry(_augustusRegistry);
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
        returns (uint256 amountOut)
    {
        (IParaSwapAugustus augustus, uint256 fromAmountOffset, bytes memory swapCalldata) =
            abi.decode(extraData, (IParaSwapAugustus, uint256, bytes));

        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);

        amountOut = _sellOnParaSwap(fromAmountOffset, swapCalldata, augustus, tokenIn, tokenOut, amountIn, minReturn);

        tokenOut.safeTransfer(msg.sender, amountOut);
    }

    function _sellOnParaSwap(
        uint256 fromAmountOffset,
        bytes memory swapCalldata,
        IParaSwapAugustus augustus,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn,
        uint256 minReturn
    )
        internal
        returns (uint256 amountOut)
    {
        if (!augustusRegistry.isValidAugustus(address(augustus))) {
            revert InvalidAugustusContract();
        }

        uint256 balanceBeforeAssetFrom = tokenIn.balanceOf(address(this));
        uint256 balanceBeforeAssetTo = tokenOut.balanceOf(address(this));

        tokenIn.safeApprove(augustus.getTokenTransferProxy(), amountIn);

        if (fromAmountOffset != 0) {
            // Ensure 256 bit (32 bytes) fromAmount value is within bounds of the
            // calldata, not overlapping with the first 4 bytes (function selector).
            if (fromAmountOffset < 4 || fromAmountOffset > swapCalldata.length - 32) {
                revert FromAmountOffsetOutOfRange(fromAmountOffset);
            }

            // Overwrite the fromAmount with the correct amount for the swap.
            // In memory, amountIn consists of a 256 bit length field, followed by
            // the actual bytes data, that is why 32 is added to the byte offset.
            assembly {
                mstore(add(swapCalldata, add(fromAmountOffset, 32)), amountIn)
            }
        }

        (bool success,) = address(augustus).call(swapCalldata);
        if (!success) {
            assembly {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }

        if (tokenIn.balanceOf(address(this)) != balanceBeforeAssetFrom - amountIn) {
            revert SwapPartiallyFilled();
        }

        amountOut = tokenOut.balanceOf(address(this)) - balanceBeforeAssetTo;
        if (amountOut < minReturn) {
            revert InsufficientAmountReceived(amountOut, minReturn);
        }

        emit Swap(address(tokenIn), address(tokenOut), amountIn, amountOut, minReturn);
    }
}
