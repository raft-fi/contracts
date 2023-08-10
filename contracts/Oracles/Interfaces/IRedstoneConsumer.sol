// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface IRedstoneConsumer {
    // --- Errors ---

    /// @dev Error if data feed ID is zero.
    error DataFeedIdCannotBeZero();

    /// @dev Error when Redstone payload is invalid.
    error RedstonePayloadIsInvalid();

    // --- Functions ---

    /// @dev Return Redstone data feed ID.
    function dataFeedId() external view returns (bytes32);

    /// @dev Return price from oracle.
    function getPrice(bytes calldata redstonePayload) external view returns (uint256);
}
