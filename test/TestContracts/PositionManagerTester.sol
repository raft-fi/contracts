// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../../contracts/PositionManager.sol";

/* Tester contract inherits from PositionManager, and provides external functions
for testing the parent's internal functions. */

contract PositionManagerTester is PositionManager {

    constructor(
        IPriceFeed _priceFeed,
        IERC20 _collateralToken,
        uint256 _positionsSize
    )
        PositionManager(_priceFeed, _collateralToken, _positionsSize)
    {
    }

    function computeICR(uint _coll, uint _debt, uint _price) external pure returns (uint) {
        return LiquityMath._computeCR(_coll, _debt, _price);
    }

    function getCollGasCompensation(uint _coll) external pure returns (uint) {
        return _getCollGasCompensation(_coll);
    }

    function getRGasCompensation() external pure returns (uint) {
        return R_GAS_COMPENSATION;
    }

    function unprotectedDecayBaseRateFromBorrowing() external returns (uint) {
        baseRate = _calcDecayedBaseRate();
        assert(baseRate >= 0 && baseRate <= DECIMAL_PRECISION);

        _updateLastFeeOpTime();
        return baseRate;
    }

    function minutesPassedSinceLastFeeOp() external view returns (uint) {
        return _minutesPassedSinceLastFeeOp();
    }

    function setLastFeeOpTimeToNow() external {
        lastFeeOperationTime = block.timestamp;
    }

    function setBaseRate(uint _baseRate) external {
        baseRate = _baseRate;
    }

    function callGetRedemptionFee(uint _ETHDrawn) external view returns (uint) {
        return _getRedemptionFee(_ETHDrawn);
    }

    function getActualDebtFromComposite(uint _debtVal) external pure returns (uint) {
        return _getNetDebt(_debtVal);
    }

    function getNewICRFromPositionChange
    (
        uint _coll,
        uint _debt,
        uint _collChange,
        bool isCollIncrease,
        uint _debtChange,
        bool isDebtIncrease,
        uint _price
    )
    external
    pure
    returns (uint)
    {
        return _getNewICRFromPositionChange(_coll, _debt, _collChange, isCollIncrease, _debtChange, isDebtIncrease, _price);
    }
}
