// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @dev Interface to be used by contracts that collect fees. Contains fee recipient that can be changed by owner.
interface IFeeCollector {
    // --- Errors ---

    /// @dev Invalid fee recipient.
    error InvalidFeeRecipient();

    // --- Events ---

    /// @dev Fee Recipient is changed to @param feeRecipient address.
    /// @param feeRecipient New fee recipient address.
    event FeeRecipientChanged(address feeRecipient);

    // --- Functions ---

    /// @return Address of the current fee recipient.
    function feeRecipient() external view returns (address);

    /// @dev Sets new fee recipient address
    /// @param newFeeRecipient Address of the new fee recipient.
    function setFeeRecipient(address newFeeRecipient) external;
}
