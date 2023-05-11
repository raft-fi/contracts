// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { ISplitLiquidationCollateral } from "../../contracts/Interfaces/ISplitLiquidationCollateral.sol";
import { PositionManager } from "../../contracts/PositionManager.sol";

contract PositionManagerHarness is PositionManager {

    IERC20 public collateralToken;

    constructor(ISplitLiquidationCollateral splitLiquidationCollateral_, IERC20 collateralToken_)
        PositionManager(splitLiquidationCollateral_) 
    { 
        collateralToken = collateralToken_;    
    }

    function managePosition(
        IERC20 collateralToken_,
        address position,
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage
    )
        external
    {
        ERC20PermitSignature memory emptySignature;
        this.managePosition(
            collateralToken_,
            position,
            collateralChange,
            isCollateralIncrease,
            debtChange,
            isDebtIncrease,
            maxFeePercentage,
            emptySignature
        );
    }

    function getRaftCollateralTokenBalance(IERC20 collateralToken_, address user) external view returns (uint256) {
        return raftCollateralTokens[collateralToken_].token.balanceOf(user);
    }
}
