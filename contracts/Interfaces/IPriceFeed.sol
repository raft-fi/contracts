// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

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
