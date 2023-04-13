// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {MathUtils} from "../../contracts/Dependencies/MathUtils.sol";

/* Tester contract for math functions in Math.sol library. */

contract MathUtilsTester {
    function MCR() external pure returns (uint256) {
        return MathUtils.MCR;
    }

    // Non-view wrapper for gas test
    function callDecPowTx(uint256 _base, uint256 _n) external pure returns (uint256) {
        return MathUtils.decPow(_base, _n);
    }

    // External wrapper
    function callDecPow(uint256 _base, uint256 _n) external pure returns (uint256) {
        return MathUtils.decPow(_base, _n);
    }
}
