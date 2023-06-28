// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FlashMintLiquidatorBase } from "./FlashMintLiquidatorBase.sol";
import { IAMM } from "./Interfaces/IAMM.sol";
import { IPositionManager } from "./Interfaces/IPositionManager.sol";

contract FlashMintLiquidator is FlashMintLiquidatorBase {
    constructor(
        IPositionManager positionManager_,
        IAMM amm_,
        IERC20 collateralToken_
    )
        FlashMintLiquidatorBase(positionManager_, amm_, collateralToken_, collateralToken_)
    // solhint-disable-next-line no-empty-blocks
    { }
}
