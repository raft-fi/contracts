// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Fixed256x18} from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import {ISplitLiquidationCollateral} from "./Interfaces/ISplitLiquidationCollateral.sol";

contract SplitLiquidationCollateral is ISplitLiquidationCollateral {
    using Fixed256x18 for uint256;

    function split(
        uint256 collateral,
        uint256 debt,
        uint256 price,
        bool isRedistribution,
        uint256 liquidationProtocolFee
    ) external pure returns (uint256 collateralToSendToProtocol, uint256 collateralToSentToLiquidator) {
        if (isRedistribution) {
            collateralToSendToProtocol = 0;
            collateralToSentToLiquidator = collateral / 200;
        } else {
            uint256 debtValue = debt.divDown(price);
            uint256 excessCollateral = collateral - debtValue;
            collateralToSendToProtocol = excessCollateral.mulDown(liquidationProtocolFee);
            collateralToSentToLiquidator = collateral - collateralToSendToProtocol;
        }
    }
}
