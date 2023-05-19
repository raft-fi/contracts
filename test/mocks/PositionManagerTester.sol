// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPriceFeed } from "../../contracts/Interfaces/IPriceFeed.sol";
import { ISplitLiquidationCollateral } from "../../contracts/Interfaces/ISplitLiquidationCollateral.sol";
import { PositionManager } from "../../contracts/PositionManager.sol";
import { MathUtils } from "../../contracts/Dependencies/MathUtils.sol";

/* Tester contract inherits from PositionManager, and provides external functions
for testing the parent's internal functions. */

contract PositionManagerTester is PositionManager {
    // solhint-disable no-empty-blocks
    constructor() PositionManager() { }
    // solhint-enable no-empty-blocks

    function unprotectedDecayBaseRateFromBorrowing(IERC20 collateralToken) external returns (uint256) {
        baseRate[collateralToken] = _calcDecayedBaseRate(collateralToken);
        assert(baseRate[collateralToken] >= 0 && baseRate[collateralToken] <= MathUtils._100_PERCENT);

        _updateLastFeeOpTime(collateralToken);
        return baseRate[collateralToken];
    }

    function setLastFeeOpTimeToNow(IERC20 collateralToken) external {
        lastFeeOperationTime[collateralToken] = block.timestamp;
    }

    function setBaseRate(IERC20 collateralToken, uint256 _baseRate) external {
        baseRate[collateralToken] = _baseRate;
    }
}
