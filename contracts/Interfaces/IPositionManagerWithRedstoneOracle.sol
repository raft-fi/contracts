// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IRedstonePriceOracle } from "../Oracles/Interfaces/IRedstonePriceOracle.sol";

interface IPositionManagerWithRedstoneOracle {
    // --- Errors ---

    /// @dev RedstonConsumerWrapper cannot be zero address.
    error RedstonePriceOracleCannotBeZeroAddress();

    /// @dev Operation is not supported.
    error NotSupported();

    // --- Functions ---

    /// @dev Return RedstonePriceOracle address.
    function redstonePriceOracle() external view returns (IRedstonePriceOracle);

    /// @dev Manages the position with the wrapped collateral token.
    /// @param collateralChange The amount of wrapped collateral token to add or remove.
    /// @param isCollateralIncrease True if the collateral is being increased, false otherwise.
    /// @param debtChange The amount of R to add or remove.
    /// @param isDebtIncrease True if the debt is being increased, false otherwise.
    /// @param maxFeePercentage The maximum fee percentage to pay for the position management.
    /// @param permitSignature The permit signature for the R token used for position repayment. Ignored in other
    /// cases.
    /// @param redstonePayload The payload for the Redstone oracle.
    function managePosition(
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        ERC20PermitSignature calldata permitSignature,
        bytes calldata redstonePayload
    )
        external;

    /// @dev Redeems the collateral from a given debt amount.
    /// @param amount The amount of debt to redeem.
    /// @param maxFeePercentage The maximum fee percentage to pay for the redemption.
    /// @param permitSignature The permit signature for the R token.
    /// @param redstonePayload The payload for the Redstone oracle.
    function redeemCollateral(
        uint256 amount,
        uint256 maxFeePercentage,
        ERC20PermitSignature calldata permitSignature,
        bytes calldata redstonePayload
    )
        external;
}
