// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

/// @dev Interface that PSM fee calculators need to follow
interface IPSMFeeCalculator {
    /// @dev Calculates fee for buying R from PSM or selling it to PSM. Should revert in case of not allowed trade.
    /// @param amount Amount of tokens coming into PSM. Expressed in R, or reserve token.
    /// @param isBuyingR True if user is buying R by depositing reserve to the PSM.
    function calculateFee(uint256 amount, bool isBuyingR) external returns (uint256 feeAmount);
}
