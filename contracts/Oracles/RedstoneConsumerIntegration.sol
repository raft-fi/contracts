// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { RedstoneConsumerNumericBase } from
    "@redstone-finance/evm-connector/contracts/core/RedstoneConsumerNumericBase.sol";
import { IRedstoneConsumerBase } from "./Interfaces/IRedstoneConsumerBase.sol";

contract RedstoneConsumerIntegration is RedstoneConsumerNumericBase, IRedstoneConsumerBase {
    // --- Constants

    bytes32 private constant DATA_FEED_ID = bytes32("STETH");

    // --- Functions ---

    // TODO This should be changed when Redstone goes live
    function getUniqueSignersThreshold() public pure override returns (uint8) {
        return 1;
    }

    // TODO This should be changed when Redstone goes live
    function getAuthorisedSignerIndex(address signerAddress) public pure override returns (uint8) {
        if (signerAddress == 0x0C39486f770B26F5527BBBf942726537986Cd7eb) {
            return 0;
        } else {
            revert SignerNotAuthorised(signerAddress);
        }
    }

    function getPrice() external view override returns (uint256) {
        return getOracleNumericValueFromTxMsg(DATA_FEED_ID);
    }
}
