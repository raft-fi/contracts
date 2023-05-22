// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC3156FlashBorrower } from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPositionManagerDependent } from "./IPositionManagerDependent.sol";
import { IAMM } from "./IAMM.sol";
import { IRToken } from "./IRToken.sol";

/// @dev Interface that OneStepLeverage needs to implement
interface IFlashMintLiquidator is IERC3156FlashBorrower, IPositionManagerDependent {
    // --- Errors ---

    /// @dev AMM cannot be zero address.
    error AmmCannotBeZero();

    /// @dev Collateral token cannot be zero address.
    error CollateralTokenCannotBeZero();

    /// @dev One step leverage supports only R token flash mints.
    error UnsupportedToken();

    /// @dev Flash mint initiator is not One Step Leverage contract.
    error InvalidInitiator();

    // --- Functions ---

    /// @dev Address of the contract that handles swaps from collateral token to R.
    function amm() external view returns (IAMM);

    /// @dev Collateral token used for leverage.
    function collateralToken() external view returns (IERC20);

    /// @dev Address of Raft debt token. Used to get amount of debt to liquidate.
    function raftDebtToken() external view returns (IERC20);

    /// @dev Address of R token.
    function rToken() external view returns (IRToken);

    /// @dev Liquidates position by:
    /// 1. Flash mint R
    /// 2. Liquidate position
    /// 3. Swap collateralToken to R
    /// 4. Repay flash mint and take profit.
    /// @param position Position to liquidate.
    /// @param ammData Additional data to pass to amm for swap.
    function liquidate(address position, bytes calldata ammData) external;
}
