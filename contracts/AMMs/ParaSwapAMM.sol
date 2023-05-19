// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAMM } from "../Interfaces/IAMM.sol";
import { IParaSwapAugustus } from "../Dependencies/IParaSwapAugustus.sol";
import { IParaSwapAugustusRegistry } from "../Dependencies/IParaSwapAugustusRegistry.sol";
import { AMMBase } from "./AMMBase.sol";
import { MsgDataManipulator } from "./MsgDataManipulator.sol";

contract ParaSwapAMM is AMMBase {
    using SafeERC20 for IERC20;
    using MsgDataManipulator for bytes;

    IParaSwapAugustusRegistry public immutable augustusRegistry;

    /// @dev Thrown when an invalid Augustus contract is provided.
    error InvalidAugustusContract();

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

        if (fromAmountOffset != 0) {
            swapCalldata.swapValueAtIndex(fromAmountOffset, amountIn);
        }

        uint256 currentAllowance = tokenIn.allowance(address(this), augustus.getTokenTransferProxy());
        if (currentAllowance != type(uint256).max) {
            tokenIn.safeIncreaseAllowance(augustus.getTokenTransferProxy(), type(uint256).max - currentAllowance);
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
