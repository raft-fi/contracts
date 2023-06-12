// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPositionManagerDependent } from "./IPositionManagerDependent.sol";
import { IAMM } from "./IAMM.sol";
import { IRToken } from "./IRToken.sol";

interface ILiquidator is IPositionManagerDependent {
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

    /// @dev Liquidates position atomically. Implementation may use flash mints, flash loans
    ///     or any other mechanism to liquidate position.
    /// @param position Position to liquidate.
    /// @param ammData Additional data to pass to amm for swap.
    function liquidate(address position, bytes calldata ammData) external;
}
