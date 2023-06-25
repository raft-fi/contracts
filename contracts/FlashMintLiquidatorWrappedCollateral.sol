// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FlashMintLiquidatorBase } from "./FlashMintLiquidatorBase.sol";
import { IAMM } from "./Interfaces/IAMM.sol";
import { IERC20Wrapped } from "./Interfaces/IERC20Wrapped.sol";
import { IPositionManager } from "./Interfaces/IPositionManager.sol";

contract FlashMintLiquidatorWrappedCollateral is FlashMintLiquidatorBase {
    using SafeERC20 for IERC20;

    constructor(
        IPositionManager positionManager_,
        IAMM amm_,
        IERC20Wrapped collateralToken_
    )
        FlashMintLiquidatorBase(positionManager_, amm_, collateralToken_, collateralToken_.underlying())
    // solhint-disable-next-line no-empty-blocks
    { }

    function _beforeSwap(uint256 swapAmount) internal override {
        IERC20Wrapped(address(collateralToken)).withdrawTo(address(this), swapAmount);
    }
}
