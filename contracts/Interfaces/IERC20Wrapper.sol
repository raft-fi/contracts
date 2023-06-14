// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Helper interface for easier integrations with wrapped collateral tokens.
interface IERC20Wrapped is IERC20 {
    function underlying() external view returns (IERC20);
    function depositFor(address account, uint256 amount) external returns (bool);
    function withdrawTo(address account, uint256 amount) external returns (bool);
}
