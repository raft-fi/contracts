// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../LQTY/LQTYStaking.sol";


contract LQTYStakingTester is LQTYStaking {

    constructor(address _collateralToken) LQTYStaking(_collateralToken) public {
    }

    function requireCallerIsTroveManager() external view {
        _requireCallerIsTroveManager();
    }
}
