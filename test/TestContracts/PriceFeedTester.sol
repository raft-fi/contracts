// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../../contracts/PriceFeed.sol";

contract PriceFeedTester is PriceFeed {

    constructor(
        AggregatorV3Interface _priceAggregator,
        ITellorCaller _tellorCaller
    )
        PriceFeed(_priceAggregator, _tellorCaller)
    {
    }

    function setLastGoodPrice(uint _lastGoodPrice) external {
        lastGoodPrice = _lastGoodPrice;
    }

    function setStatus(Status _status) external {
        status = _status;
    }
}
