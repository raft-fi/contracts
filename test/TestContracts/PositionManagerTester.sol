// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPriceFeed} from "../../contracts/Interfaces/IPriceFeed.sol";
import {PositionManager} from "../../contracts/PositionManager.sol";
import {MathUtils} from "../../contracts/Dependencies/MathUtils.sol";

/* Tester contract inherits from PositionManager, and provides external functions
for testing the parent's internal functions. */

contract PositionManagerTester is PositionManager {
    constructor(
        IPriceFeed _priceFeed,
        IERC20 _collateralToken,
        uint256 _positionsSize,
        uint256 _liquidationProtocolFee,
        address[] memory delegates
    ) PositionManager(_priceFeed, _collateralToken, _positionsSize, _liquidationProtocolFee, delegates) {}

    function getCollLiquidationProtocolFee(uint256 _entireColl, uint256 _entireDebt, uint256 _price, uint256)
        external
        view
        returns (uint256 fee)
    {
        (fee,) = splitLiquidationCollateral(_entireColl, _entireDebt, _price, false);
    }

    function unprotectedDecayBaseRateFromBorrowing() external returns (uint256) {
        baseRate = _calcDecayedBaseRate();
        assert(baseRate >= 0 && baseRate <= MathUtils._100_PERCENT);

        _updateLastFeeOpTime();
        return baseRate;
    }

    function setLastFeeOpTimeToNow() external {
        lastFeeOperationTime = block.timestamp;
    }

    function setBaseRate(uint256 _baseRate) external {
        baseRate = _baseRate;
    }
}
