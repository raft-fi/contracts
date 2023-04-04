// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../../contracts/Dependencies/MathUtils.sol";

/* Tester contract for math functions in Math.sol library. */

contract MathUtilsTester {
    function MIN_NET_DEBT() external pure returns (uint) {
        return MathUtils.MIN_NET_DEBT;
    }

    function R_GAS_COMPENSATION() external pure returns (uint) {
        return MathUtils.R_GAS_COMPENSATION;
    }

    function MCR() external pure returns (uint) {
        return MathUtils.MCR;
    }

    // Non-view wrapper for gas test
    function callDecPowTx(uint _base, uint _n) external returns (uint) {
        return MathUtils.decPow(_base, _n);
    }

    // External wrapper
    function callDecPow(uint _base, uint _n) external pure returns (uint) {
        return MathUtils.decPow(_base, _n);
    }

    function getCompositeDebt(uint _debt) external pure returns (uint) {
        return MathUtils.getCompositeDebt(_debt);
    }
}
