// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPositionManagerDependent {
    function positionManager() external view returns (address);
}
