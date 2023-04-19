// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Fixed256x18} from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import {ISplitLiquidationCollateral} from "./Interfaces/ISplitLiquidationCollateral.sol";

contract SplitLiquidationCollateral is ISplitLiquidationCollateral {
    using Fixed256x18 for uint256;

    uint256 private constant LOW_TOTAL_COLLATERAL = 3_000e18;
    uint256 private constant MEDIUM_TOTAL_COLLATERAL = 100_000e18;
    uint256 private constant HIGH_TOTAL_COLLATERAL = 1_000_000e18;

    uint256 private constant LOW_REDISTRUBTOR_REWARD_RATE = 300e14;
    uint256 private constant MEDIUM_REDISTRUBTOR_REWARD_RATE = 125e14;
    uint256 private constant HIGH_REDISTRUBTOR_REWARD_RATE = 50e14;

    function split(
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 price,
        bool isRedistribution,
        uint256 liquidationProtocolFee
    ) external pure returns (uint256 collateralToSendToProtocol, uint256 collateralToSentToLiquidator) {
        if (isRedistribution) {
            collateralToSendToProtocol = 0;
            collateralToSentToLiquidator =
                totalCollateral.mulDown(_calculateRedistributorRewardRate(totalCollateral)).divDown(1e18);
        } else {
            uint256 debtValue = totalDebt.divDown(price);
            uint256 excessCollateral = totalCollateral - debtValue;
            collateralToSendToProtocol = excessCollateral.mulDown(liquidationProtocolFee);
            collateralToSentToLiquidator = totalCollateral - collateralToSendToProtocol;
        }
    }

    function _calculateRedistributorRewardRate(uint256 totalCollateral) internal pure returns (uint256) {
        if (totalCollateral <= LOW_TOTAL_COLLATERAL) {
            return LOW_REDISTRUBTOR_REWARD_RATE;
        }
        if (totalCollateral <= MEDIUM_TOTAL_COLLATERAL) {
            return _calculateRedistributorRewardRateFormula(
                totalCollateral,
                LOW_TOTAL_COLLATERAL,
                MEDIUM_TOTAL_COLLATERAL,
                LOW_REDISTRUBTOR_REWARD_RATE,
                MEDIUM_REDISTRUBTOR_REWARD_RATE
            );
        }
        if (totalCollateral <= HIGH_TOTAL_COLLATERAL) {
            return _calculateRedistributorRewardRateFormula(
                totalCollateral,
                MEDIUM_TOTAL_COLLATERAL,
                HIGH_TOTAL_COLLATERAL,
                MEDIUM_REDISTRUBTOR_REWARD_RATE,
                HIGH_REDISTRUBTOR_REWARD_RATE
            );
        }
        return HIGH_REDISTRUBTOR_REWARD_RATE;
    }

    // Formula from https://docs.raft.fi/how-it-works/returning/redistribution#redistributor-reward
    function _calculateRedistributorRewardRateFormula(
        uint256 collateral,
        uint256 collateralUpperBound,
        uint256 collateraLowerBound,
        uint256 redistributorRewardRateUpperBound,
        uint256 redistributorRewardRateLowerBound
    ) internal pure returns (uint256) {
        return redistributorRewardRateUpperBound
            - (redistributorRewardRateUpperBound - redistributorRewardRateLowerBound).mulDown(
                collateral - collateralUpperBound
            ).divDown(collateraLowerBound - collateralUpperBound);
    }
}
