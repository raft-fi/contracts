// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../../contracts/ActivePool.sol";

contract ActivePoolTester is ActivePool {

    constructor(address _collateralToken) ActivePool(_collateralToken) {
    }

    function unprotectedIncreaseRDebt(uint _amount) external {
        rDebt  = rDebt + _amount;
    }
}
