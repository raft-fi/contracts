// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface ITellor {
    // --- Functions ---

    function getDataBefore(
        bytes32 queryId,
        uint256 timestamp
    )
        external
        view
        returns (bool ifRetrieve, bytes memory value, uint256 timestampRetrieved);
}
