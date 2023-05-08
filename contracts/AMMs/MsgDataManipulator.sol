// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

library MsgDataManipulator {
    /// @dev Thrown provided with an out of range index for the given bytes data.
    /// @param index The invalid index.
    /// @param msgDataLength The size of the bytes data.
    error IndexOutOfRange(uint256 index, uint256 msgDataLength);

    function swapValueAtIndex(bytes memory data, uint256 index, uint256 value) internal pure {
        // Ensure 256 bit (32 bytes) value is within bounds of the
        // calldata, not overlapping with the first 4 bytes (function selector).
        if (index < 4 || index > data.length - 32) {
            revert IndexOutOfRange(index, data.length);
        }

        // In memory, value consists of a 256 bit length field, followed by
        // the actual bytes data, that is why 32 is added to the byte offset.
        assembly {
            mstore(add(data, add(index, 32)), value)
        }
    }
}
