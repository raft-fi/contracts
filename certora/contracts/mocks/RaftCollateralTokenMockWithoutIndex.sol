// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ERC20MockBase } from "./ERC20MockBase.sol";

contract RaftCollateralTokenMockWithoutIndex is ERC20MockBase {
    // solhint-disable-next-line no-empty-blocks
    function setIndex(uint256 backingAmount) external { }
}
