// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVault } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import { OneInchV5AMM } from "./OneInchV5AMM.sol";
import { BalancerAMM } from "./BalancerAMM.sol";

contract OneInchV5BalancerAMM is OneInchV5AMM, BalancerAMM {
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
            IERC20 intermediaryToken,
            uint256 intermediaryMinReturn,
            bool isOneInchFirst,
            bytes memory oneInchAMMData,
            bytes memory balancerAMMData
        ) = abi.decode(extraData, (IERC20, uint256, bool, bytes, bytes));

        if (isOneInchFirst) {
            OneInchV5AMM._executeSwap(tokenIn, amountIn, intermediaryMinReturn, oneInchAMMData);
            BalancerAMM._executeSwap(
                intermediaryToken, intermediaryToken.balanceOf(address(this)), minReturn, balancerAMMData
            );
        } else {
            BalancerAMM._executeSwap(tokenIn, amountIn, intermediaryMinReturn, balancerAMMData);
            OneInchV5AMM._executeSwap(
                intermediaryToken, intermediaryToken.balanceOf(address(this)), minReturn, oneInchAMMData
            );
        }
    }
}
