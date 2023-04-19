// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ITellor {
    // --- Functions ---

    /// @dev Counts the number of values that have been submitted for the request. If called for the `currentRequest`
    /// being mined it can tell you how many miners have submitted a value for that request so far.
    /// @param requestID The request ID to look up.
    /// @return Count of the number of values received for the request ID.
    function getNewValueCountbyRequestId(uint256 requestID) external view returns (uint256);

    /// @dev Gets the timestamp for the value based on their index.
    /// @param requestID The request ID to look up.
    /// @param index The value index to look up.
    /// @return The timestamp.
    function getTimestampbyRequestIDandIndex(uint256 requestID, uint256 index) external view returns (uint256);

    /// @dev Retrieve value from oracle based on timestamp
    /// @param requestID The request ID being requested.
    /// @param timestamp Timestamp to retrieve data/value from.
    /// @return Value for timestamp submitted.
    function retrieveData(uint256 requestID, uint256 timestamp) external view returns (uint256);
}
