// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "./Interfaces/IFeeCollector.sol";

abstract contract FeeCollector is Ownable2Step, IFeeCollector {
    address public override feeRecipient;

    /// @param _feeRecipient Address of the fee recipient to initialize contract with.
    constructor(address _feeRecipient) {
        if (_feeRecipient == address(0)) {
            revert InvalidFeeRecipient();
        }

        feeRecipient = _feeRecipient;
    }

    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        if (newFeeRecipient == address(0)) {
            revert InvalidFeeRecipient();
        }

        feeRecipient = newFeeRecipient;
        emit FeeRecipientChanged(newFeeRecipient);
    }
}
