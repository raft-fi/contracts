// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../contracts/ActivePool.sol";

contract ActivePoolTester is ActivePool {

    constructor(IERC20 _collateralToken) ActivePool(_collateralToken) {
    }

    function unprotectedIncreaseRDebt(uint _amount) external {
        rDebt  = rDebt + _amount;
    }
}
