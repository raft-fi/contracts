// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../../contracts/PriceFeed.sol";

contract PriceFeedTester is PriceFeed {

    constructor(IPriceOracle _primaryOracle, IPriceOracle _secondaryOracle) PriceFeed(_primaryOracle, _secondaryOracle) {
    }
    
    function setLastGoodPrice(uint _lastGoodPrice) external {
        lastGoodPrice = _lastGoodPrice;
    }
}
