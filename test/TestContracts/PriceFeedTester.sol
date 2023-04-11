// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../../contracts/PriceFeed.sol";

contract PriceFeedTester is PriceFeed {

    constructor(IPriceOracle _primaryOracle, IPriceOracle _secondaryOracle) PriceFeed(_primaryOracle, _secondaryOracle, 5e16) {
    }
    
    function setLastGoodPrice(uint _lastGoodPrice) external {
        lastGoodPrice = _lastGoodPrice;
    }
}
