// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IPriceOracle } from "./IPriceOracle.sol";
import { IRedstoneConsumer } from "./IRedstoneConsumer.sol";

interface IRedstonePriceOracle is IPriceOracle {
    // --- Events ---

    /// @dev Emitted when price is set.
    /// @param price Price that is set.
    /// @param timestamp Timestamp when price is set.
    /// @param isBroken True if oracle response is broken.
    event PriceSet(uint256 indexed price, uint256 indexed timestamp, bool isBroken);

    // --- Errors ---

    /// @dev User didn't set price from Redstone in this block.
    error PriceIsNotSetInThisBlock();

    /// @dev RedstoneConsumer address cannot be zero address.
    error RedstoneConsumerCannotBeZeroAddress();

    /// @dev Redstone payload is invalid.
    error RedstonePayloadIsInvalid();

    // --- Functions ---

    /// @dev Return Redstone consumer base address.
    function redstoneConsumer() external view returns (IRedstoneConsumer);

    /// @dev Return last fetched price.
    function lastPrice() external view returns (uint256);

    /// @dev Return last update timestamp.
    function lastUpdateTimestamp() external view returns (uint256);

    /// @dev Return true if oracle response is broken.
    function isBrokenOrFrozen() external view returns (bool);

    /// @dev Set price from oracle, last update timestamp and isBrokenOrFrozen flag.
    function setPrice(bytes calldata redstonePayload) external;
}
