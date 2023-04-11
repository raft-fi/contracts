// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { MathUtils } from "./Dependencies/MathUtils.sol";
import { IPriceFeed } from "./Interfaces/IPriceFeed.sol";
import { IPriceOracle, PriceOracleResponse } from "./Oracles/Interfaces/IPriceOracle.sol";

contract PriceFeed is IPriceFeed, Ownable2Step {
    IPriceOracle public override primaryOracle;
    IPriceOracle public override secondaryOracle;

    uint256 public override lastGoodPrice;

    uint256 public override priceDifferenceBetweenOracles;

    uint256 private constant MIN_PRICE_DIFFERENCE_BETWEEN_ORACLES = 1e15; // 0.1%
    uint256 private constant MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES = 1e17; // 10%

    constructor(
        IPriceOracle _primaryOracle, 
        IPriceOracle _secondaryOracle, 
        uint256 _priceDifferenceBetweenOracles
    ) {
        _setPrimaryOracle(_primaryOracle);
        _setSecondaryOracle(_secondaryOracle);
        _setPriceDifferenceBetweenOracle(_priceDifferenceBetweenOracles);
    }

    // --- Functions ---

    function setPrimaryOracle(IPriceOracle _primaryOracle) external override onlyOwner {
        _setPrimaryOracle(_primaryOracle);
    }

    function setSecondaryOracle(IPriceOracle _secondaryOracle) external override onlyOwner {
        _setSecondaryOracle(_secondaryOracle);
    }

    function setPriceDifferenceBetweenOracles(uint256 _priceDifferenceBetweenOracles) external override onlyOwner {
        _setPriceDifferenceBetweenOracle(_priceDifferenceBetweenOracles);
    }

    function fetchPrice() external override returns (uint256 price) {
        PriceOracleResponse memory primaryOracleResponse = primaryOracle.getPriceOracleResponse();
        // If primary oracle is broken or frozen, try secondary oracle
        if (primaryOracleResponse.isBrokenOrFrozen) {
            // If secondary oracle is broken then both oracles are untrusted, so return the last good price
            PriceOracleResponse memory secondaryOracleResponse = secondaryOracle.getPriceOracleResponse();
            if (secondaryOracleResponse.isBrokenOrFrozen || secondaryOracleResponse.priceChangeAboveMax) {
                return lastGoodPrice;
            }

            return _storePrice(secondaryOracleResponse.price);
        }

        // If primary oracle price has changed by > 50% between two consecutive rounds, compare it to secondary oracle's
        // price
        if (primaryOracleResponse.priceChangeAboveMax) {
            PriceOracleResponse memory secondaryOracleResponse = secondaryOracle.getPriceOracleResponse();
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

            // If both oracle are live and have different prices, return the price that is a lower changed between the two oracle's prices
            return _storePrice(_getPriceWithLowerChange(primaryOracleResponse.price, secondaryOracleResponse.price));
        }

        // If primary oracle is working, return primary oracle current price
        return _storePrice(primaryOracleResponse.price);
    }

    // --- Helper functions ---
    
    function _bothOraclesSimilarPrice(
        uint256 _primaryOraclePrice,
        uint256 _secondaryOraclePrice
    )
        internal
        view
        returns (bool)
    {
        // Get the relative price difference between the oracles. Use the lower price as the denominator, i.e. the
        // reference for the calculation.
        uint256 minPrice = Math.min(_primaryOraclePrice, _secondaryOraclePrice);
        uint256 maxPrice = Math.max(_primaryOraclePrice, _secondaryOraclePrice);
        uint256 percentPriceDifference = (maxPrice - minPrice) * MathUtils.DECIMAL_PRECISION / minPrice;

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
        uint256 _primaryOraclePrice,
        uint256 _secondaryOraclePrice
    ) 
        internal
        view
        returns (uint256)
    {
        if (_primaryOraclePrice > lastGoodPrice && _secondaryOraclePrice > lastGoodPrice) {
            return Math.min(_primaryOraclePrice, _secondaryOraclePrice);
        }
        if (_primaryOraclePrice < lastGoodPrice && _secondaryOraclePrice < lastGoodPrice) {
            return Math.max(_primaryOraclePrice, _secondaryOraclePrice);
        }
        return lastGoodPrice;
    }

    function _setPrimaryOracle(IPriceOracle _primaryOracle) internal {
        if (address(_primaryOracle) == address(0)) {
            revert InvalidPrimaryOracle();
        }

        PriceOracleResponse memory primaryOracleResponse = _primaryOracle.getPriceOracleResponse();

        if (primaryOracleResponse.isBrokenOrFrozen || primaryOracleResponse.priceChangeAboveMax) {
            revert PrimaryOracleBrokenOrFrozenOrBadResult();
        }

        primaryOracle = _primaryOracle;

        // Get an initial price from primary oracle to serve as first reference for lastGoodPrice
        _storePrice(primaryOracleResponse.price);

        emit PrimaryOracleUpdated(_primaryOracle);
    }

    function _setSecondaryOracle(IPriceOracle _secondaryOracle) internal {
        if (address(_secondaryOracle) == address(0)) {
            revert InvalidSecondaryOracle();
        }

        secondaryOracle = _secondaryOracle;

        emit SecondaryOracleUpdated(_secondaryOracle);
    }

    function _setPriceDifferenceBetweenOracle(uint256 _priceDifferenceBetweenOracles) internal {
        if (_priceDifferenceBetweenOracles < MIN_PRICE_DIFFERENCE_BETWEEN_ORACLES 
            || _priceDifferenceBetweenOracles > MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES
        ) {
            revert InvalidPriceDifferenceBetweenOracles();
        }

        priceDifferenceBetweenOracles = _priceDifferenceBetweenOracles;

        emit PriceDifferenceBetweenOraclesUpdated(_priceDifferenceBetweenOracles);
    }

    function _storePrice(uint256 _currentPrice) internal returns (uint256) {
        lastGoodPrice = _currentPrice;
        emit LastGoodPriceUpdated(_currentPrice);
        return _currentPrice;
    }
}
