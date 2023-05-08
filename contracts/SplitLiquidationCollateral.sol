// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { ISplitLiquidationCollateral } from "./Interfaces/ISplitLiquidationCollateral.sol";

contract SplitLiquidationCollateral is ISplitLiquidationCollateral {
    // --- Types ---

    using Fixed256x18 for uint256;

    // --- Constants ---

    uint256 private constant LOW_TOTAL_COLLATERAL = 3000e18;
    uint256 private constant MEDIUM_TOTAL_COLLATERAL = 100_000e18;
    uint256 private constant HIGH_TOTAL_COLLATERAL = 1_000_000e18;

    uint256 private constant LOW_REDISTRIBUTOR_REWARD_RATE = 300e14;
    uint256 private constant MEDIUM_REDISTRIBUTOR_REWARD_RATE = 125e14;
    uint256 private constant HIGH_REDISTRIBUTOR_REWARD_RATE = 50e14;

    uint256 private constant LOW_LIQUIDATOR_REWARD_RATE = 1e18;
    uint256 private constant MEDIUM_LIQUIDATOR_REWARD_RATE = 65e16;
    uint256 private constant HIGH_LIQUIDATOR_REWARD_RATE = 50e16;

    uint256 public constant override LOW_TOTAL_DEBT = 3000e18;
    uint256 private constant MEDIUM_TOTAL_DEBT = 100_000e18;
    uint256 private constant HIGH_TOTAL_DEBT = 1_000_000e18;

    // --- Functions ---

    function split(
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 price,
        bool isRedistribution
    )
        external
        pure
        returns (uint256 collateralToSendToProtocol, uint256 collateralToSentToLiquidator)
    {
        if (isRedistribution) {
            uint256 collateralValue = totalCollateral.mulDown(price);
            uint256 rewardRate = _calculateRedistributorRewardRate(collateralValue);
            collateralToSentToLiquidator = totalCollateral.mulDown(rewardRate);
        } else {
            uint256 matchingCollateral = totalDebt.divDown(price);
            uint256 excessCollateral = totalCollateral - matchingCollateral;
            uint256 liquidatorReward = excessCollateral.mulDown(_calculateLiquidatorRewardRate(totalDebt));
            collateralToSendToProtocol = excessCollateral - liquidatorReward;
            collateralToSentToLiquidator = liquidatorReward + matchingCollateral;
        }
    }

    // Formula from https://docs.raft.fi/how-it-works/returning/redistribution#redistributor-reward
    function _calculateRedistributorRewardRate(uint256 collateralValue) internal pure returns (uint256) {
        if (collateralValue <= LOW_TOTAL_COLLATERAL) {
            return LOW_REDISTRIBUTOR_REWARD_RATE;
        }
        if (collateralValue <= MEDIUM_TOTAL_COLLATERAL) {
            return _calculateRewardRateFormula(
                collateralValue,
                LOW_TOTAL_COLLATERAL,
                MEDIUM_TOTAL_COLLATERAL,
                LOW_REDISTRIBUTOR_REWARD_RATE,
                MEDIUM_REDISTRIBUTOR_REWARD_RATE
            );
        }
        if (collateralValue <= HIGH_TOTAL_COLLATERAL) {
            return _calculateRewardRateFormula(
                collateralValue,
                MEDIUM_TOTAL_COLLATERAL,
                HIGH_TOTAL_COLLATERAL,
                MEDIUM_REDISTRIBUTOR_REWARD_RATE,
                HIGH_REDISTRIBUTOR_REWARD_RATE
            );
        }
        return HIGH_REDISTRIBUTOR_REWARD_RATE;
    }

    // Formula from https://docs.raft.fi/how-it-works/returning/liquidation#liquidator-reward
    function _calculateLiquidatorRewardRate(uint256 totalDebt) internal pure returns (uint256) {
        if (totalDebt <= LOW_TOTAL_DEBT) {
            return LOW_LIQUIDATOR_REWARD_RATE;
        }
        if (totalDebt <= MEDIUM_TOTAL_DEBT) {
            return _calculateRewardRateFormula(
                totalDebt, LOW_TOTAL_DEBT, MEDIUM_TOTAL_DEBT, LOW_LIQUIDATOR_REWARD_RATE, MEDIUM_LIQUIDATOR_REWARD_RATE
            );
        }
        if (totalDebt <= HIGH_TOTAL_DEBT) {
            return _calculateRewardRateFormula(
                totalDebt,
                MEDIUM_TOTAL_DEBT,
                HIGH_TOTAL_DEBT,
                MEDIUM_LIQUIDATOR_REWARD_RATE,
                HIGH_LIQUIDATOR_REWARD_RATE
            );
        }
        return HIGH_LIQUIDATOR_REWARD_RATE;
    }

    function _calculateRewardRateFormula(
        uint256 amount,
        uint256 amountUpperBound,
        uint256 amountLowerBound,
        uint256 rewardRateUpperBound,
        uint256 rewardRateLowerBound
    )
        internal
        pure
        returns (uint256)
    {
        return rewardRateUpperBound
            - (rewardRateUpperBound - rewardRateLowerBound).mulDown(amount - amountUpperBound).divDown(
                amountLowerBound - amountUpperBound
            );
    }
}
