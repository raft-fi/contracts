// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IPriceOracle} from "../../contracts/Oracles/Interfaces/IPriceOracle.sol";
import {PriceFeed} from "../../contracts/PriceFeed.sol";

contract PriceFeedTester is PriceFeed {
    // solhint-disable no-empty-blocks
    constructor(IPriceOracle _primaryOracle, IPriceOracle _secondaryOracle)
        PriceFeed(_primaryOracle, _secondaryOracle, 5e16)
    {}
    // solhint-enable no-empty-blocks

    function setLastGoodPrice(uint256 _lastGoodPrice) external {
        lastGoodPrice = _lastGoodPrice;
    }
}
