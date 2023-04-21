// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStETH is IERC20 {
    // --- Functions ---

    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256);

    function getSharesByPooledEth(uint256 pooledEthAmount) external view returns (uint256);

    function submit(address referral) external payable returns (uint256);
}
