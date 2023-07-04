// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IVault } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import { IAsset } from "@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";
import { OneInchV5AMM } from "./OneInchV5AMM.sol";
import { BalancerAMM } from "./BalancerAMM.sol";
import { MsgDataManipulator } from "./MsgDataManipulator.sol";

contract OneInchV5BalancerAMM is OneInchV5AMM, BalancerAMM {
    using SafeERC20 for IERC20;
    using MsgDataManipulator for bytes;
    using SafeCast for uint256;

    constructor(address _aggregationRouter, IVault _vault) OneInchV5AMM(_aggregationRouter) BalancerAMM(_vault) { }

    function _executeSwap(
        IERC20 tokenIn,
        uint256 amountIn,
        uint256 minReturn,
        bytes memory extraData
    )
        internal
        override(OneInchV5AMM, BalancerAMM)
    {
        (
            IVault.BatchSwapStep[] memory swaps,
            IAsset[] memory assets,
            uint256 deadline,
            uint256 fromAmountOffset,
            bytes memory swapCalldata
        ) = abi.decode(extraData, (IVault.BatchSwapStep[], IAsset[], uint256, uint256, bytes));

        /// OneInch step
        if (fromAmountOffset != 0) {
            swapCalldata.swapValueAtIndex(fromAmountOffset, amountIn);
        }

        uint256 currentAllowance = tokenIn.allowance(address(this), address(aggregationRouter));
        if (currentAllowance != type(uint256).max) {
            tokenIn.safeIncreaseAllowance(address(aggregationRouter), type(uint256).max - currentAllowance);
        }

        IERC20 intermediaryToken = IERC20(address(assets[0]));
        uint256 intermediaryBalanceBefore = intermediaryToken.balanceOf(address(this));
        (bool success,) = aggregationRouter.call(swapCalldata);
        if (!success) {
            assembly {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
        uint256 intermediaryBalanceReceived = intermediaryToken.balanceOf(address(this)) - intermediaryBalanceBefore;

        /// Balancer step
        int256[] memory limits = new int256[](assets.length);
        limits[0] = intermediaryBalanceReceived.toInt256();
        limits[limits.length - 1] = -minReturn.toInt256();

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        currentAllowance = intermediaryToken.allowance(address(this), address(vault));
        if (currentAllowance != type(uint256).max) {
            intermediaryToken.safeIncreaseAllowance(address(vault), type(uint256).max - currentAllowance);
        }

        swaps[0].amount = intermediaryBalanceReceived;
        vault.batchSwap(IVault.SwapKind.GIVEN_IN, swaps, assets, funds, limits, deadline);
    }
}
