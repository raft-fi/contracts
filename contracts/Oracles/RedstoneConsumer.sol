// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { PrimaryProdDataServiceConsumerBase } from
    "@redstone-finance/evm-connector/contracts/data-services/PrimaryProdDataServiceConsumerBase.sol";
import { IRedstoneConsumer } from "./Interfaces/IRedstoneConsumer.sol";

contract RedstoneConsumer is PrimaryProdDataServiceConsumerBase, IRedstoneConsumer {
    // --- Immutable variables ---

    bytes32 public immutable override dataFeedId;

    // --- Constructor ---

    constructor(bytes32 _dataFeedId) PrimaryProdDataServiceConsumerBase() {
        if (_dataFeedId == 0) {
            revert DataFeedIdCannotBeZero();
        }
        dataFeedId = _dataFeedId;
    }

    // --- Functions ---

    function getPrice(bytes calldata) external view override returns (uint256) {
        return getOracleNumericValueFromTxMsg(dataFeedId);
    }
}
