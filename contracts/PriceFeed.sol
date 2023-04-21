// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { MathUtils } from "./Dependencies/MathUtils.sol";
import { IPriceFeed } from "./Interfaces/IPriceFeed.sol";
import { IPriceOracle } from "./Oracles/Interfaces/IPriceOracle.sol";

contract PriceFeed is IPriceFeed, Ownable2Step {
    // --- Types ---

    using Fixed256x18 for uint256;

    // --- Constants ---

    uint256 private constant MIN_PRICE_DIFFERENCE_BETWEEN_ORACLES = 1e15; // 0.1%
    uint256 private constant MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES = 1e17; // 10%

    // --- Variables ---

    IPriceOracle public override primaryOracle;
    IPriceOracle public override secondaryOracle;

    uint256 public override lastGoodPrice;

    uint256 public override priceDifferenceBetweenOracles;

    // --- Constructor ---

    constructor(IPriceOracle primaryOracle_, IPriceOracle secondaryOracle_, uint256 priceDifferenceBetweenOracles_) {
        _setPrimaryOracle(primaryOracle_);
        _setSecondaryOracle(secondaryOracle_);
        _setPriceDifferenceBetweenOracle(priceDifferenceBetweenOracles_);
    }

    // --- Functions ---

    function setPrimaryOracle(IPriceOracle newPrimaryOracle) external override onlyOwner {
        _setPrimaryOracle(newPrimaryOracle);
    }

    function setSecondaryOracle(IPriceOracle newSecondaryOracle) external override onlyOwner {
        _setSecondaryOracle(newSecondaryOracle);
    }

    function setPriceDifferenceBetweenOracles(uint256 newPriceDifferenceBetweenOracles) external override onlyOwner {
        _setPriceDifferenceBetweenOracle(newPriceDifferenceBetweenOracles);
    }

    function fetchPrice() external override returns (uint256 price) {
        IPriceOracle.PriceOracleResponse memory primaryOracleResponse = primaryOracle.getPriceOracleResponse();
        // If primary oracle is broken or frozen, try secondary oracle
        if (primaryOracleResponse.isBrokenOrFrozen) {
            // If secondary oracle is broken then both oracles are untrusted, so return the last good price
            IPriceOracle.PriceOracleResponse memory secondaryOracleResponse = secondaryOracle.getPriceOracleResponse();
            if (secondaryOracleResponse.isBrokenOrFrozen || secondaryOracleResponse.priceChangeAboveMax) {
                return lastGoodPrice;
            }

            return _storePrice(secondaryOracleResponse.price);
        }

        // If primary oracle price has changed by > 50% between two consecutive rounds, compare it to secondary
        // oracle's price
        if (primaryOracleResponse.priceChangeAboveMax) {
            IPriceOracle.PriceOracleResponse memory secondaryOracleResponse = secondaryOracle.getPriceOracleResponse();
            // If primary oracle is broken or frozen, both oracles are untrusted, and return last good price
            if (secondaryOracleResponse.isBrokenOrFrozen) {
                return lastGoodPrice;
            }

            /*
            * If the secondary oracle is live and both oracles have a similar price, conclude that the primary oracle's
            * large price deviation between two consecutive rounds were likely a legitimate market price movement, so
            * continue using primary oracle
            */
            if (_bothOraclesSimilarPrice(primaryOracleResponse.price, secondaryOracleResponse.price)) {
                return _storePrice(primaryOracleResponse.price);
            }

            // If both oracle are live and have different prices, return the price that is a lower changed between the
            // two oracle's prices
            return _storePrice(_getPriceWithLowerChange(primaryOracleResponse.price, secondaryOracleResponse.price));
        }

        // If primary oracle is working, return primary oracle current price
        return _storePrice(primaryOracleResponse.price);
    }

    // --- Helper functions ---

    function _bothOraclesSimilarPrice(
        uint256 primaryOraclePrice,
        uint256 secondaryOraclePrice
    )
        internal
        view
        returns (bool)
    {
        // Get the relative price difference between the oracles. Use the lower price as the denominator, i.e. the
        // reference for the calculation.
        uint256 minPrice = Math.min(primaryOraclePrice, secondaryOraclePrice);
        uint256 maxPrice = Math.max(primaryOraclePrice, secondaryOraclePrice);
        uint256 percentPriceDifference = (maxPrice - minPrice).divDown(minPrice);

        /*
        * Return true if the relative price difference is <= 3%: if so, we assume both oracles are probably reporting
        * the honest market price, as it is unlikely that both have been broken/hacked and are still in-sync.
        */
        return percentPriceDifference <= priceDifferenceBetweenOracles;
    }

    // @dev Returns one of oracles' prices that deviates least from the last good price.
    //      If both oracles' prices are above the last good price, return the lower one.
    //      If both oracles' prices are below the last good price, return the higher one.
    //      Otherwise, return the last good price.
    function _getPriceWithLowerChange(
        uint256 primaryOraclePrice,
        uint256 secondaryOraclePrice
    )
        internal
        view
        returns (uint256)
    {
        if (primaryOraclePrice > lastGoodPrice && secondaryOraclePrice > lastGoodPrice) {
            return Math.min(primaryOraclePrice, secondaryOraclePrice);
        }
        if (primaryOraclePrice < lastGoodPrice && secondaryOraclePrice < lastGoodPrice) {
            return Math.max(primaryOraclePrice, secondaryOraclePrice);
        }
        return lastGoodPrice;
    }

    function _setPrimaryOracle(IPriceOracle newPrimaryOracle) internal {
        if (address(newPrimaryOracle) == address(0)) {
            revert InvalidPrimaryOracle();
        }

        IPriceOracle.PriceOracleResponse memory primaryOracleResponse = newPrimaryOracle.getPriceOracleResponse();

        if (primaryOracleResponse.isBrokenOrFrozen || primaryOracleResponse.priceChangeAboveMax) {
            revert PrimaryOracleBrokenOrFrozenOrBadResult();
        }

        primaryOracle = newPrimaryOracle;

        // Get an initial price from primary oracle to serve as first reference for lastGoodPrice
        _storePrice(primaryOracleResponse.price);

        emit PrimaryOracleUpdated(newPrimaryOracle);
    }

    function _setSecondaryOracle(IPriceOracle newSecondaryOracle) internal {
        if (address(newSecondaryOracle) == address(0)) {
            revert InvalidSecondaryOracle();
        }

        secondaryOracle = newSecondaryOracle;

        emit SecondaryOracleUpdated(newSecondaryOracle);
    }

    function _setPriceDifferenceBetweenOracle(uint256 newPriceDifferenceBetweenOracles) internal {
        if (
            newPriceDifferenceBetweenOracles < MIN_PRICE_DIFFERENCE_BETWEEN_ORACLES
                || newPriceDifferenceBetweenOracles > MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES
        ) {
            revert InvalidPriceDifferenceBetweenOracles();
        }

        priceDifferenceBetweenOracles = newPriceDifferenceBetweenOracles;

        emit PriceDifferenceBetweenOraclesUpdated(newPriceDifferenceBetweenOracles);
    }

    function _storePrice(uint256 currentPrice) internal returns (uint256) {
        lastGoodPrice = currentPrice;
        emit LastGoodPriceUpdated(currentPrice);
        return currentPrice;
    }
}
