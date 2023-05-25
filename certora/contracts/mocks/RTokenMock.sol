// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ERC20MockBase } from "./ERC20MockBase.sol";

contract RTokenMock is ERC20MockBase {
    /* solhint-disable no-empty-blocks */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        public
    { }
    /* solhint-enable no-empty-blocks */
}
