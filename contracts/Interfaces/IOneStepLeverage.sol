// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManagerDependent} from "./IPositionManagerDependent.sol";
import {IAMM} from "./IAMM.sol";

/// @dev Interface that OneStepLeverage needs to implement
interface IOneStepLeverage is IERC3156FlashBorrower, IPositionManagerDependent {
    /// @dev One step leverage supports only R token flash mints.
    error UnsupportedToken();

    /// @dev Flash mint initiator is not One Step Leverage contract.
    error InvalidInitiator();

    /// @dev Maximum amount of R tokens to be leftover as dust after managing leveraged position call.
    /// In particular some dust can be left after decreasing leverage because swap is done from collateral to R.
    /// Since we specify amount of collateral to swap it will result in >= (flashMintAmount + flashMintFee).
    /// If the result is larger than flash mint repayment amount we will pay it back to user only if it is greater
    /// than `MAX_LEFTOVER_R`.
    function MAX_LEFTOVER_R() external view returns (uint256);

    /// @dev Address of the contract that handles swaps between collateral token and R.
    function amm() external view returns (IAMM);

    /// @dev Collateral token used for leverage.
    function collateralToken() external view returns (IERC20);

    /// @dev Increases or decreases leverage for a position.
    /// @param debtChange Debt being added or removed.
    /// @param isDebtIncrease True if increasing debt/leverage.
    /// @param principalCollChange Principal collateral change (collateral added/removed from/to user wallet).
    /// @param principalCollIncrease True if principal collateral is added.
    /// @param ammData Additional data to pass to swap method in amm.
    /// @param minReturnOrAmountToSell Serves for two different purposes:
    /// - leverage increase: it is min amount of collateral token to get from swapping flash minted R.
    /// - leverage decrease: it is amount of collateral to swap that will result with enough R to repay flash mint.
    /// @param maxFeePercentage The maximum fee percentage to pay for the position management.
    /// @notice In case of closing position by decreasing debt to zero principalCollIncrease must be false,
    /// and principalCollChange + minReturnOrAmountToSell should be equal to total collateral balance of user.
    function manageLeveragedPosition(
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 principalCollChange,
        bool principalCollIncrease,
        bytes calldata ammData,
        uint256 minReturnOrAmountToSell,
        uint256 maxFeePercentage
    ) external;
}
