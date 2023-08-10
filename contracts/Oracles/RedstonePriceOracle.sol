// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { RedstoneDefaultsLib } from "@redstone-finance/evm-connector/contracts/core/RedstoneDefaultsLib.sol";
import { IWstETH } from "../Dependencies/IWstETH.sol";
import { IRedstoneConsumer } from "./Interfaces/IRedstoneConsumer.sol";
import { IRedstonePriceOracle } from "./Interfaces/IRedstonePriceOracle.sol";
import { BasePriceOracle } from "./BasePriceOracle.sol";

contract RedstonePriceOracle is IRedstonePriceOracle, BasePriceOracle {
    // --- Constants ---

    uint256 public constant override DEVIATION = 0; // 0% because they fetch price in 10 seconds

    uint256 private constant _DECIMALS = 8;

    // --- Immutable variables ---

    IRedstoneConsumer public immutable override redstoneConsumer;

    // --- Variables ---

    uint256 public override lastPrice;
    uint256 public override lastUpdateTimestamp;
    bool public override isBrokenOrFrozen;

    // --- Constructor ---

    constructor(IRedstoneConsumer _redstoneConsumer, uint256 _timeout) BasePriceOracle(_timeout) {
        if (address(_redstoneConsumer) == address(0)) {
            revert RedstoneConsumerCannotBeZeroAddress();
        }
        redstoneConsumer = _redstoneConsumer;
    }

    // --- Functions ---

    function getPriceOracleResponse() external override returns (PriceOracleResponse memory response) {
        if (block.timestamp != lastUpdateTimestamp) {
            revert PriceIsNotSetInThisBlock();
        }
        response.isBrokenOrFrozen = isBrokenOrFrozen;
        if (!response.isBrokenOrFrozen) {
            response.price = _formatPrice(lastPrice, _DECIMALS);
        }
    }

    function setPrice(bytes calldata redstonePayload) external {
        try redstoneConsumer.getPrice(redstonePayload) returns (uint256 oraclePrice) {
            lastPrice = oraclePrice;
            lastUpdateTimestamp = block.timestamp;
            isBrokenOrFrozen = false;
            emit PriceSet(oraclePrice, block.timestamp, false);
        } catch (bytes memory reason) {
            bytes4 selectorTimestampFromTooLongFuture = RedstoneDefaultsLib.TimestampFromTooLongFuture.selector;
            bytes4 selectorTimestampIsTooOld = RedstoneDefaultsLib.TimestampIsTooOld.selector;
            bytes4 receivedSelector = bytes4(reason);
            if (
                receivedSelector == selectorTimestampFromTooLongFuture || receivedSelector == selectorTimestampIsTooOld
            ) {
                isBrokenOrFrozen = true;
                emit PriceSet(0, 0, true);
            } else {
                revert RedstonePayloadIsInvalid();
            }
        }
    }
}
