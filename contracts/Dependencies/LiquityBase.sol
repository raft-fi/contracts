// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./BaseMath.sol";
import "./LiquityMath.sol";
import "../Interfaces/IActivePool.sol";
import "../Interfaces/IDefaultPool.sol";
import "../Interfaces/IPriceFeed.sol";
import "../Interfaces/ILiquityBase.sol";

/// @dev Fee exceeded provided maximum fee percentage
error FeeExceedsMaxFee(uint fee, uint amount, uint maxFeePercentage);

/*
* Base contract for TroveManager and BorrowerOperations. Contains global system constants and
* common functions.
*/
contract LiquityBase is BaseMath, ILiquityBase {
    uint constant public _100pct = 1000000000000000000; // 1e18 == 100%

    // Minimum collateral ratio for individual troves
    uint constant public MCR = 1100000000000000000; // 110%

    // Amount of R to be locked in gas pool on opening troves
    uint constant public R_GAS_COMPENSATION = 200e18;

    // Minimum amount of net R debt a trove must have
    uint constant public MIN_NET_DEBT = 1800e18;
    // uint constant public MIN_NET_DEBT = 0;

    uint constant public PERCENT_DIVISOR = 200; // dividing by 200 yields 0.5%

    IActivePool public override activePool;

    IDefaultPool public override defaultPool;

    IPriceFeed public override priceFeed;

    // --- Gas compensation functions ---

    // Returns the composite debt (drawn debt + gas compensation) of a trove, for the purpose of ICR calculation
    function _getCompositeDebt(uint _debt) internal pure returns (uint) {
        return _debt + R_GAS_COMPENSATION;
    }

    function _getNetDebt(uint _debt) internal pure returns (uint) {
        return _debt - R_GAS_COMPENSATION;
    }

    // Return the amount of collateralToken to be drawn from a trove's collateral and sent as gas compensation.
    function _getCollGasCompensation(uint _entireColl) internal pure returns (uint) {
        return _entireColl / PERCENT_DIVISOR;
    }

    /// @dev Returns active and liquidated collateral.
    function getEntireSystemColl() public view returns (uint entireSystemColl) {
        entireSystemColl = activePool.collateralBalance() + defaultPool.collateralBalance();
    }

    /// @dev Returns active and closed debt.
    function getEntireSystemDebt() public view returns (uint entireSystemDebt) {
        entireSystemDebt = activePool.getRDebt() + defaultPool.getRDebt();
    }

    function _getTCR(uint _price) internal view returns (uint TCR) {
        TCR = LiquityMath._computeCR(getEntireSystemColl(), getEntireSystemDebt(), _price);
    }

    function _requireUserAcceptsFee(uint _fee, uint _amount, uint _maxFeePercentage) internal pure {
        uint feePercentage = _fee * DECIMAL_PRECISION / _amount;

        if (feePercentage > _maxFeePercentage) {
            revert FeeExceedsMaxFee(_fee, _amount, _maxFeePercentage);
        }
    }
}
