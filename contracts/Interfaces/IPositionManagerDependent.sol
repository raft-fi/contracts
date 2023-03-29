// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IPositionManager.sol";

interface IPositionManagerDependent {
    function positionManager() external view returns (IPositionManager);
}
