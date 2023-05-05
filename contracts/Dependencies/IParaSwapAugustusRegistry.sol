// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IParaSwapAugustusRegistry {
    function isValidAugustus(address augustus) external view returns (bool);
}
