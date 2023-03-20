// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../DefaultPool.sol";

contract DefaultPoolTester is DefaultPool {
    function unprotectedIncreaseLUSDDebt(uint256 _amount) external {
        LUSDDebt += _amount;
    }

    function unprotectedPayable() external payable {
        ETH += msg.value;
    }
}
