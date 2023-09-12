// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IERC20Indexable } from "../Interfaces/IERC20Indexable.sol";
import { IPositionManager } from "../Interfaces/IPositionManager.sol";
import { IPriceFeed } from "../Interfaces/IPriceFeed.sol";
import { IRToken } from "../Interfaces/IRToken.sol";
import { ISplitLiquidationCollateral } from "../Interfaces/ISplitLiquidationCollateral.sol";

/// @dev Common interface for the Position Manager.
interface IInterestRatePositionManager is IPositionManager {
    // --- Events ---

    /// @dev Fees coming from accrued interest are minted.
    /// @param collateralToken Collateral token that fees are paid for.
    /// @param amount Amount of R minted.
    event MintedFees(IERC20 collateralToken, uint256 amount);

    // --- Errors ---

    /// @dev Only registered debt token can be caller.
    /// @param sender Actual caller.
    error InvalidDebtToken(address sender);

    // --- Functions ---

    /// @dev Mints fees coming from accrued interest. Can be called only from matching debt token.
    /// @param collateralToken Collateral token to mint fees for.
    /// @param amount Amount of R to mint.
    function mintFees(IERC20 collateralToken, uint256 amount) external;
}
