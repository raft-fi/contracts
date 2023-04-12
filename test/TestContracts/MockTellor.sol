// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ITellor} from "../../contracts/Dependencies/ITellor.sol";

contract MockTellor is ITellor {
    // --- Mock price data ---

    bool private didRetrieve = true; // default to a positive retrieval
    uint256 private price;
    uint256 private updateTime;

    bool private revertRequest;

    // --- Setters for mock price data ---

    function setPrice(uint256 _price) external {
        price = _price;
    }

    function setDidRetrieve(bool _didRetrieve) external {
        didRetrieve = _didRetrieve;
    }

    function setUpdateTime(uint256 _updateTime) external {
        updateTime = _updateTime;
    }

    function setRevertRequest() external {
        revertRequest = !revertRequest;
    }

    // --- Mock data reporting functions ---

    function getTimestampbyRequestIDandIndex(uint256, uint256) external view returns (uint256) {
        return updateTime;
    }

    function getNewValueCountbyRequestId(uint256) external view returns (uint256) {
        if (revertRequest) require(1 == 0, "Tellor request reverted");
        return 1;
    }

    function retrieveData(uint256, uint256) external view returns (uint256) {
        return price;
    }
}
