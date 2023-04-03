// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./Dependencies/MathUtils.sol";
import "./Interfaces/IPriceFeed.sol";

contract PriceFeed is IPriceFeed, Ownable2Step {
    IPriceOracle public override primaryOracle;
    IPriceOracle public override secondaryOracle;

    uint256 public override lastGoodPrice;

    uint256 constant public override MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES = 5e16; // 5%

    constructor(IPriceOracle _primaryOracle, IPriceOracle _secondaryOracle) {
        _setPrimaryOracle(_primaryOracle);
        _setSecondaryOracle(_secondaryOracle);
    }

    // --- Functions ---

    function setPrimaryOracle(IPriceOracle _primaryOracle) external override onlyOwner {
        _setPrimaryOracle(_primaryOracle);
    }
    
    function setSecondaryOracle(IPriceOracle _secondaryOracle) external override onlyOwner {
        _setSecondaryOracle(_secondaryOracle);
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

        // If primary oracle price has changed by > 50% between two consecutive rounds, compare it to secondary oracle's price
        if (primaryOracleResponse.priceChangeAboveMax) {
            PriceOracleResponse memory secondaryOracleResponse = secondaryOracle.getPriceOracleResponse();
            // If primary oracle is broken or frozen, both oracles are untrusted, and return last good price
            if (secondaryOracleResponse.isBrokenOrFrozen) {
                return lastGoodPrice;
            }

            /*
            * If the secondary oracle is live and both oracles have a similar price, conclude that the primary oracle's large price deviation between
            * two consecutive rounds were likely a legitimate market price movement, so continue using primary oracle
            */
            if (_bothOraclesSimilarPrice(primaryOracleResponse.price, secondaryOracleResponse.price)) {
                return _storePrice(primaryOracleResponse.price);
            }

            // If secondary oracle is live but the oracles differ too much in price, conclude that primary oracle initial price deviation was
            // an oracle failure and use secondary oracle price
            return _storePrice(secondaryOracleResponse.price);
        }

        // If primary oracle is working, return primary oracle current price
        return _storePrice(primaryOracleResponse.price);
    }

    // --- Helper functions ---    
    function _bothOraclesSimilarPrice(uint256 primaryOraclePrice, uint256 secondaryOraclePrice) internal pure returns (bool) {
        // Get the relative price difference between the oracles. Use the lower price as the denominator, i.e. the reference for the calculation.
        uint256 minPrice = Math.min(primaryOraclePrice, secondaryOraclePrice);
        uint256 maxPrice = Math.max(primaryOraclePrice, secondaryOraclePrice);
        uint256 percentPriceDifference = (maxPrice - minPrice) * MathUtils.DECIMAL_PRECISION / minPrice;

        /*
        * Return true if the relative price difference is <= 3%: if so, we assume both oracles are probably reporting
        * the honest market price, as it is unlikely that both have been broken/hacked and are still in-sync.
        */
        return percentPriceDifference <= MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES;
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
    }

    function _setSecondaryOracle(IPriceOracle _secondaryOracle) internal {
        if (address(_secondaryOracle) == address(0)) {
            revert InvalidSecondaryOracle();
        }
        
        secondaryOracle = _secondaryOracle;
    }

    function _storePrice(uint256 _currentPrice) internal returns(uint256) {
        lastGoodPrice = _currentPrice;
        emit LastGoodPriceUpdated(_currentPrice);
        return _currentPrice;
    }
}
