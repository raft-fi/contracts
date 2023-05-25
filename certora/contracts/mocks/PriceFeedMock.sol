// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IPriceFeed } from "../../../contracts/Interfaces/IPriceFeed.sol";
import { IPriceOracle } from "../../../contracts/Oracles/Interfaces/IPriceOracle.sol";

contract PriceFeedMock is IPriceFeed {
    uint256 public priceDifferenceBetweenOracles;

    uint256 public lastGoodPrice;

    uint256 public deviation;

    IPriceOracle public override primaryOracle;
    IPriceOracle public override secondaryOracle;

    function fetchPrice() external view override returns (uint256, uint256) {
        return (lastGoodPrice, deviation);
    }

    // solhint-disable-next-line no-empty-blocks
    function setPrimaryOracle(IPriceOracle _primaryOracle) external { }

    // solhint-disable-next-line no-empty-blocks
    function setSecondaryOracle(IPriceOracle _secondaryOracle) external { }

    // solhint-disable-next-line no-empty-blocks
    function setPriceDifferenceBetweenOracles(uint256 _priceDifferenceBetweenOracles) external { }
}
