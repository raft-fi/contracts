// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../ActivePool.sol";

contract ActivePoolTester is ActivePool {

    function unprotectedIncreaseLUSDDebt(uint _amount) external {
        LUSDDebt  = LUSDDebt + _amount;
    }

    function unprotectedPayable() external payable {
        ETH = ETH + msg.value;
    }
}
