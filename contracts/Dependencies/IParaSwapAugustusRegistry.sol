// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface IParaSwapAugustusRegistry {
    function isValidAugustus(address augustus) external view returns (bool);
}
