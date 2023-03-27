// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../contracts/DefaultPool.sol";

contract DefaultPoolTester is DefaultPool {

    constructor(IERC20 _collateralToken) DefaultPool(_collateralToken) {
    }
}
