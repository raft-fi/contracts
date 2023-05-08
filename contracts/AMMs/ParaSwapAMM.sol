// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAMM } from "../Interfaces/IAMM.sol";
import { IParaSwapAugustus } from "../Dependencies/IParaSwapAugustus.sol";
import { IParaSwapAugustusRegistry } from "../Dependencies/IParaSwapAugustusRegistry.sol";
import { AMMBase } from "./AMMBase.sol";

contract ParaSwapAMM is AMMBase {
    using SafeERC20 for IERC20;

    IParaSwapAugustusRegistry public immutable augustusRegistry;

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

    function _executeSwap(IERC20 tokenIn, uint256 amountIn, uint256, bytes calldata extraData) internal override {
        (IParaSwapAugustus augustus, uint256 fromAmountOffset, bytes memory swapCalldata) =
            abi.decode(extraData, (IParaSwapAugustus, uint256, bytes));

        if (!augustusRegistry.isValidAugustus(address(augustus))) {
            revert InvalidAugustusContract();
        }

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
    }
}
