// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @dev Invalid fee recipient.
error InvalidFeeRecipient();

interface IFeeCollector {
    event FeeRecipientChanged(address _feeRecipient);

    function feeRecipient() external view returns (address);

    function setFeeRecipient(address _feeRecipient) external;
}
