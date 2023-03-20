// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../ActivePool.sol";

contract ActivePoolTester is ActivePool {
    function unprotectedIncreaseLUSDDebt(uint256 _amount) external {
        LUSDDebt += _amount;
    }

    function unprotectedPayable() external payable {
        ETH += msg.value;
    }
}
