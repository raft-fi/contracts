// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IFeeCollector} from "./Interfaces/IFeeCollector.sol";

abstract contract FeeCollector is Ownable2Step, IFeeCollector {
    // --- Variables ---

    address public override feeRecipient;

    // --- Constructor ---

    /// @param feeRecipient_ Address of the fee recipient to initialize contract with.
    constructor(address feeRecipient_) {
        if (feeRecipient_ == address(0)) {
            revert InvalidFeeRecipient();
        }

        feeRecipient = feeRecipient_;
    }

    // --- Functions ---

    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        if (newFeeRecipient == address(0)) {
            revert InvalidFeeRecipient();
        }

        feeRecipient = newFeeRecipient;
        emit FeeRecipientChanged(newFeeRecipient);
    }
}
