// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWstETH is IERC20 {
    // --- Functions ---

    function stETH() external returns (IERC20);

    /// @notice Exchanges stETH to wstETH
    /// @param stETHAmount amount of stETH to wrap in exchange for wstETH
    /// @dev Requirements:
    ///  - `stETHAmount` must be non-zero
    ///  - msg.sender must approve at least `stETHAmount` stETH to this
    ///    contract.
    ///  - msg.sender must have at least `stETHAmount` of stETH.
    /// User should first approve `stETHAmount` to the WstETH contract
    /// @return Amount of wstETH user receives after wrap
    function wrap(uint256 stETHAmount) external returns (uint256);

    /// @notice Exchanges wstETH to stETH.
    /// @param wstETHAmount Amount of wstETH to unwrap in exchange for stETH.
    /// @dev Requirements:
    ///  - `wstETHAmount` must be non-zero
    ///  - msg.sender must have at least `wstETHAmount` wstETH.
    /// @return Amount of stETH user receives after unwrap.
    function unwrap(uint256 wstETHAmount) external returns (uint256);

    /// @notice Get amount of wstETH for a given amount of stETH.
    /// @param stETHAmount Amount of stETH.
    /// @return Amount of wstETH for a given stETH amount.
    function getWstETHByStETH(uint256 stETHAmount) external view returns (uint256);

    /// @notice Get amount of stETH for a given amount of wstETH.
    /// @param wstETHAmount amount of wstETH.
    /// @return Amount of stETH for a given wstETH amount.
    function getStETHByWstETH(uint256 wstETHAmount) external view returns (uint256);

    /// @notice Get amount of stETH for a one wstETH.
    /// @return Amount of stETH for 1 wstETH.
    function stEthPerToken() external view returns (uint256);

    /// @notice Get amount of wstETH for a one stETH.
    /// @return Amount of wstETH for a 1 stETH.
    function tokensPerStEth() external view returns (uint256);
}
