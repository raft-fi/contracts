// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { IPriceFeed } from "../../contracts/Interfaces/IPriceFeed.sol";
import { IPriceOracle } from "../../contracts/Oracles/Interfaces/IPriceOracle.sol";

/*
* PriceFeed placeholder for testnet and development. The price is simply set manually and saved in a state
* variable. The contract does not connect to a live Chainlink price feed.*/
contract PriceFeedTestnet is IPriceFeed {
    uint256 private _price = 200 * 1e18;
    uint256 private constant DEVIATION = 5e15; // 0.5%

    IPriceOracle public override primaryOracle;
    IPriceOracle public override secondaryOracle;

    uint256 public override lastGoodPrice;

    uint256 public override priceDifferenceBetweenOracles;

    // --- Functions ---

    // View price getter for simplicity in tests
    function getPrice() external view returns (uint256) {
        return _price;
    }

    function fetchPrice() external override returns (uint256, uint256) {
        // Fire an event just like the mainnet version would.
        // This lets the subgraph rely on events to get the latest price even when developing locally.
        emit LastGoodPriceUpdated(_price);
        return (_price, DEVIATION);
    }

    // Manual external price setter.
    function setPrice(uint256 price) external returns (bool) {
        _price = price;
        return true;
    }

    // solhint-disable-next-line no-empty-blocks
    function setPrimaryOracle(IPriceOracle _primaryOracle) external { }

    // solhint-disable-next-line no-empty-blocks
    function setSecondaryOracle(IPriceOracle _secondaryOracle) external { }

    // solhint-disable-next-line no-empty-blocks
    function setPriceDifferenceBetweenOracles(uint256 _priceDifferenceBetweenOracles) external { }
}
