// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IVault } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import { IAsset } from "@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAMM } from "../Interfaces/IAMM.sol";
import { AMMBase } from "./AMMBase.sol";

contract BalancerAMM is AMMBase {
    using SafeERC20 for IERC20;

    /// @dev Thrown when provided with a zero address Balancer Vault as a constructor argument.
    error ZeroAddressVault();

    IVault public immutable vault;

    constructor(IVault _vault) {
        if (address(_vault) == address(0)) {
            revert ZeroAddressVault();
        }
        vault = _vault;
    }

    function _executeSwap(
        IERC20 tokenIn,
        uint256 amountIn,
        uint256 minReturn,
        bytes calldata extraData
    )
        internal
        override
    {
        (IVault.BatchSwapStep[] memory swaps, IAsset[] memory assets, uint256 deadline) =
            abi.decode(extraData, (IVault.BatchSwapStep[], IAsset[], uint256));

        int256[] memory limits = new int256[](assets.length);
        limits[0] = int256(amountIn);
        limits[limits.length - 1] = -int256(minReturn);

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        uint256 currentAllowance = tokenIn.allowance(address(this), address(vault));
        if (currentAllowance != type(uint256).max) {
            tokenIn.safeIncreaseAllowance(address(vault), type(uint256).max - currentAllowance);
        }

        swaps[0].amount = amountIn;
        vault.batchSwap(IVault.SwapKind.GIVEN_IN, swaps, assets, funds, limits, deadline);
    }
}
