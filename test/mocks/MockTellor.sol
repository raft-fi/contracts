// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ITellor } from "../../contracts/Dependencies/ITellor.sol";

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

    function getDataBefore(bytes32, uint256) external view returns (bool, bytes memory, uint256) {
        return (true, _toBytes(price), updateTime);
    }

    function _toBytes(uint256 x) internal pure returns (bytes memory b) {
        b = new bytes(32);
        assembly {
            mstore(add(b, 32), x)
        }
    }
}
