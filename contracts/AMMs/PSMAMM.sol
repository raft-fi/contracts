// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAMM } from "../Interfaces/IAMM.sol";
import { IPSM } from "../PSM/IPSM.sol";
import { AMMBase } from "./AMMBase.sol";

contract PSMAMM is AMMBase {
    error ZeroAddress();
    error InvalidTokenIn();

    IPSM public immutable psm;

    constructor(IPSM _psm) {
        if (address(_psm) == address(0)) {
            revert ZeroAddress();
        }
        psm = _psm;
        _psm.reserveToken().approve(address(_psm), type(uint256).max);
        _psm.rToken().approve(address(_psm), type(uint256).max);
    }

    function _executeSwap(
        IERC20 tokenIn,
        uint256 amountIn,
        uint256 minReturn,
        bytes memory
    )
        internal
        virtual
        override
    {
        if (tokenIn == psm.reserveToken()) {
            psm.buyR(amountIn, minReturn);
        } else if (tokenIn == psm.rToken()) {
            psm.buyReserveToken(amountIn, minReturn);
        } else {
            revert InvalidTokenIn();
        }
    }
}
