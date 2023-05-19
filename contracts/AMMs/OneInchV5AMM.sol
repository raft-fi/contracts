// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AMMBase } from "./AMMBase.sol";
import { MsgDataManipulator } from "./MsgDataManipulator.sol";

contract OneInchV5AMM is AMMBase {
    using SafeERC20 for IERC20;
    using MsgDataManipulator for bytes;

    /// @dev Thrown when provided with a zero address Aggregation Router constructor argument.
    error ZeroAddressAggregationRouter();

    address public immutable aggregationRouter;

    constructor(address _aggregationRouter) {
        if (_aggregationRouter == address(0)) {
            revert ZeroAddressAggregationRouter();
        }
        aggregationRouter = _aggregationRouter;
    }

    function _executeSwap(IERC20 tokenIn, uint256 amountIn, uint256, bytes calldata extraData) internal override {
        (uint256 fromAmountOffset, bytes memory swapCalldata) = abi.decode(extraData, (uint256, bytes));

        if (fromAmountOffset != 0) {
            swapCalldata.swapValueAtIndex(fromAmountOffset, amountIn);
        }

        uint256 currentAllowance = tokenIn.allowance(address(this), address(aggregationRouter));
        if (currentAllowance != type(uint256).max) {
            tokenIn.safeIncreaseAllowance(address(aggregationRouter), type(uint256).max - currentAllowance);
        }

        (bool success,) = aggregationRouter.call(swapCalldata);
        if (!success) {
            assembly {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
    }
}
