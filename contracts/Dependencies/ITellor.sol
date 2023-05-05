// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ITellor {
    // --- Functions ---

    /// @dev Returns the total number of values submitted for a given @param queryId
    /// @param queryId The tellor query ID to look up.
    /// @return Count of the number of values received for the request ID.
    function getNewValueCountbyQueryId(bytes32 queryId) external view returns (uint256);

    /// @dev Returns the timestamp at a specific index for a given @param queryId.
    /// @param queryId The tellor query ID to look up.
    /// @param index The value index to look up.
    /// @return The timestamp.
    function getTimestampbyQueryIdandIndex(bytes32 queryId, uint256 index) external view returns (uint256);

    /// @dev Retrieves a specific value by queryId and timestamp
    /// @param queryId The tellor query ID to look up.
    /// @param timestamp Timestamp to retrieve data/value from.
    /// @return Value for timestamp submitted.
    function retrieveData(bytes32 queryId, uint256 timestamp) external view returns (bytes memory);
}
