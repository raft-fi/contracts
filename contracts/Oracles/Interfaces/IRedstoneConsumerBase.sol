// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IRedstoneConsumerBase {
    // --- Functions ---

    /// @dev Return price from oracle.
    function getPrice() external view returns (uint256);
}
