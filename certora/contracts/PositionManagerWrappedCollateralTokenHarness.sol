// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IERC20Indexable } from "../../contracts/Interfaces/IERC20Indexable.sol";
import { IPriceFeed } from "../../contracts/Interfaces/IPriceFeed.sol";
import { ISplitLiquidationCollateral } from "../../contracts/Interfaces/ISplitLiquidationCollateral.sol";
import {
    IERC20Wrapped,
    IPositionManager,
    PositionManagerWrappedCollateralToken
} from "../../contracts/PositionManagerWrappedCollateralToken.sol";
import { IRToken } from "../../contracts/RToken.sol";

contract PositionManagerWrappedCollateralTokenHarness is PositionManagerWrappedCollateralToken {
    IERC20Indexable public raftDebtTokenHarness;
    IERC20Indexable public raftCollateralTokenHarness;

    IERC20 public collateralTokenHarness;

    IRToken public rToken;

    IPriceFeed public priceFeedHarness;
    ISplitLiquidationCollateral public splitLiquidationCollateralHarness;

    /* solhint-disable no-empty-blocks */
    constructor(
        address positionManager_,
        IERC20Wrapped wrappedCollateralToken_
    )
        PositionManagerWrappedCollateralToken(positionManager_, wrappedCollateralToken_)
    { }
    /* solhint-enable no-empty-blocks */

    function collateralInfo(IERC20 collateralToken)
        external
        view
        returns (
            IERC20Indexable raftCollateralToken,
            IERC20Indexable raftDebtToken,
            IPriceFeed priceFeed,
            ISplitLiquidationCollateral splitLiquidation,
            bool isEnabled,
            uint256 lastFeeOperationTime,
            uint256 borrowingSpread,
            uint256 baseRate,
            uint256 redemptionSpread,
            uint256 redemptionRebate
        )
    {
        return IPositionManager(positionManager).collateralInfo(collateralToken);
    }

    function managePositionHarness(
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        ERC20PermitSignature calldata permitSignature
    )
        external
    {
        super.managePosition(
            collateralChange, isCollateralIncrease, debtChange, isDebtIncrease, maxFeePercentage, permitSignature
        );
    }

    function redeemCollateralHarness(
        uint256 debtAmount,
        uint256 maxFeePercentage,
        ERC20PermitSignature calldata permitSignature
    )
        external
    {
        super.redeemCollateral(debtAmount, maxFeePercentage, permitSignature);
    }

    function getRToken() external view returns (IRToken) {
        return _rToken;
    }

    function getRaftDebtToken() external view returns (IERC20Indexable) {
        return _raftDebtToken;
    }

    function feeRecipient() external view returns (address) {
        return IPositionManager(positionManager).feeRecipient();
    }
}
