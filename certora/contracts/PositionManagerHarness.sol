// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Indexable } from "../../contracts/Interfaces/IERC20Indexable.sol";
import { IPriceFeed } from "../../contracts/Interfaces/IPriceFeed.sol";
import { ISplitLiquidationCollateral } from "../../contracts/Interfaces/ISplitLiquidationCollateral.sol";
import { PositionManager, MathUtils } from "../../contracts/PositionManager.sol";

contract PositionManagerHarness is PositionManager {
    IERC20 public collateralTokenHarness;

    IERC20Indexable public raftDebtTokenHarness;
    IERC20Indexable public raftCollateralTokenHarness;

    IPriceFeed public priceFeedHarness;
    ISplitLiquidationCollateral public splitLiquidationCollateralHarness;

    // solhint-disable-next-line no-empty-blocks
    constructor() PositionManager(address(0)) { }

    function computeICR(address position, uint256 price) external view returns (uint256) {
        IERC20 collateralToken = collateralTokenForPosition[position];
        CollateralTokenInfo storage collateralTokenInfo = collateralInfo[collateralToken];
        uint256 entireCollateral = collateralTokenInfo.collateralToken.balanceOf(position);
        uint256 entireDebt = collateralTokenInfo.debtToken.balanceOf(position);
        return MathUtils._computeCR(entireCollateral, entireDebt, price);
    }
}
