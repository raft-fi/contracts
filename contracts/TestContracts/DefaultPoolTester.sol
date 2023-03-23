// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../DefaultPool.sol";

contract DefaultPoolTester is DefaultPool {

    constructor(address _collateralToken) DefaultPool(_collateralToken) public {

    }
}
