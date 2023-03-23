// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../ActivePool.sol";

contract ActivePoolTester is ActivePool {

    constructor(address _collateralToken) ActivePool(_collateralToken) public {
    }

    function unprotectedIncreaseLUSDDebt(uint _amount) external {
        LUSDDebt  = LUSDDebt + _amount;
    }
}
