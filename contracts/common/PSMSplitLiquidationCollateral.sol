// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ISplitLiquidationCollateral } from "../Interfaces/ISplitLiquidationCollateral.sol";
import { MathUtils } from "../Dependencies/MathUtils.sol";

contract PSMSplitLiquidationCollateral is ISplitLiquidationCollateral {
    error NotSupported();

    uint256 public constant override LOW_TOTAL_DEBT = 1;
    uint256 public constant override MCR = MathUtils._100_PERCENT;

    function split(uint256, uint256, uint256, bool) external pure returns (uint256, uint256) {
        revert NotSupported();
    }
}
