// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

/// @dev Chainlink is broken or frozen.
error ChainlinkBroken();

interface IPriceFeed {
    enum Status {
        chainlinkWorking,
        usingTellorChainlinkUntrusted,
        bothOraclesUntrusted,
        usingTellorChainlinkFrozen,
        usingChainlinkTellorUntrusted
    }

    // --- Events ---
    event LastGoodPriceUpdated(uint _lastGoodPrice);
    event PriceFeedStatusChanged(Status newStatus);

    // --- Function ---
    function fetchPrice() external returns (uint);
}
