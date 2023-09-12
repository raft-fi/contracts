// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.19;

import { IPriceFeed } from "../Interfaces/IPriceFeed.sol";
import { IPriceOracle } from "../Oracles/Interfaces/IPriceOracle.sol";
import { Lock } from "./Lock.sol";

/// @dev Price oracle to be used for peg stability module to mint R.
/// Returns constant price of 1 USD per token with 0 deviation.
contract ConstantPriceFeed is IPriceFeed, Lock {
    /// @dev Thrown in case action is not supported
    error NotSupported();

    IPriceOracle public override primaryOracle;
    IPriceOracle public override secondaryOracle;

    uint256 public constant override lastGoodPrice = 1e18;
    uint256 public override priceDifferenceBetweenOracles;

    constructor(address unlocker) Lock(unlocker) { }

    function setPrimaryOracle(IPriceOracle) external pure override {
        revert NotSupported();
    }

    function setSecondaryOracle(IPriceOracle) external pure override {
        revert NotSupported();
    }

    function setPriceDifferenceBetweenOracles(uint256) external pure override {
        revert NotSupported();
    }

    function fetchPrice() external view override whenUnlocked returns (uint256, uint256) {
        return (lastGoodPrice, 0);
    }
}
