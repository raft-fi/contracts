// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVault } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import { ParaSwapAMM } from "./ParaSwapAMM.sol";
import { BalancerAMM } from "./BalancerAMM.sol";

contract ParaSwapBalancerAMM is ParaSwapAMM, BalancerAMM {
    constructor(address _augustusRegistry, IVault _vault) ParaSwapAMM(_augustusRegistry) BalancerAMM(_vault) { }

    function _executeSwap(
        IERC20 tokenIn,
        uint256 amountIn,
        uint256 minReturn,
        bytes memory extraData
    )
        internal
        override(ParaSwapAMM, BalancerAMM)
    {
        (
            IERC20 intermediaryToken,
            uint256 intermediaryMinReturn,
            bool isParaSwapFirst,
            bytes memory paraSwapAMMData,
            bytes memory BalancerAMMData
        ) = abi.decode(extraData, (IERC20, uint256, bool, bytes, bytes));

        if (isParaSwapFirst) {
            ParaSwapAMM._executeSwap(tokenIn, amountIn, intermediaryMinReturn, paraSwapAMMData);
            BalancerAMM._executeSwap(
                intermediaryToken, intermediaryToken.balanceOf(address(this)), minReturn, BalancerAMMData
            );
        } else {
            BalancerAMM._executeSwap(tokenIn, amountIn, intermediaryMinReturn, BalancerAMMData);
            ParaSwapAMM._executeSwap(
                intermediaryToken, intermediaryToken.balanceOf(address(this)), minReturn, paraSwapAMMData
            );
        }
    }
}
