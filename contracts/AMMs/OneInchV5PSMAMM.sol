// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPSM } from "../PSM/IPSM.sol";
import { OneInchV5AMM } from "./OneInchV5AMM.sol";
import { PSMAMM } from "./PSMAMM.sol";

contract OneInchV5PSMAMM is OneInchV5AMM, PSMAMM {
    constructor(address _aggregationRouter, IPSM _psm) OneInchV5AMM(_aggregationRouter) PSMAMM(_psm) { }

    function _executeSwap(
        IERC20 tokenIn,
        uint256 amountIn,
        uint256 minReturn,
        bytes memory extraData
    )
        internal
        override(OneInchV5AMM, PSMAMM)
    {
        (IERC20 intermediaryToken, uint256 intermediaryMinReturn, bool isOneInchFirst, bytes memory oneInchAMMData) =
            abi.decode(extraData, (IERC20, uint256, bool, bytes));

        if (isOneInchFirst) {
            OneInchV5AMM._executeSwap(tokenIn, amountIn, intermediaryMinReturn, oneInchAMMData);
            PSMAMM._executeSwap(intermediaryToken, intermediaryToken.balanceOf(address(this)), minReturn, "");
        } else {
            PSMAMM._executeSwap(tokenIn, amountIn, intermediaryMinReturn, "");
            OneInchV5AMM._executeSwap(
                intermediaryToken, intermediaryToken.balanceOf(address(this)), minReturn, oneInchAMMData
            );
        }
    }
}
