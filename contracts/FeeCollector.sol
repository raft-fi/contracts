// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "./Interfaces/IFeeCollector.sol";

contract FeeCollector is Ownable2Step, IFeeCollector {
    address public override feeRecipient;

    constructor(address _feeRecipient) {
        if (_feeRecipient == address(0)) {
            revert InvalidFeeRecipient();
        }

        feeRecipient = _feeRecipient;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) {
            revert InvalidFeeRecipient();
        }

        feeRecipient = _feeRecipient;
        emit FeeRecipientChanged(_feeRecipient);
    }
}
