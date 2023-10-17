// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { AggregatorV3Interface } from "@smartcontractkit/chainlink/interfaces/AggregatorV3Interface.sol";
import { IPriceOracle } from "../contracts/Oracles/Interfaces/IPriceOracle.sol";
import { ChainlinkPriceOracle } from "../contracts/Oracles/ChainlinkPriceOracle.sol";

contract ChainlinkPriceOracleBTC is Test {
    AggregatorV3Interface public constant AGGREGATOR_V3_BTC =
        AggregatorV3Interface(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);
    ChainlinkPriceOracle public chainlinkPriceOracleBTC;

    function setUp() public {
        vm.createSelectFork("mainnet", 18_362_477);

        chainlinkPriceOracleBTC = new ChainlinkPriceOracle(AGGREGATOR_V3_BTC, 5e15, 3 hours, 18, 15e16);
    }

    function testChainlinkBTCPrice() public {
        vm.warp(1_697_454_698);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = chainlinkPriceOracleBTC.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, false);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertApproxEqAbs(priceOracleResponse.price, 27_784e18, 1e18);
    }

    function testCheckDeployedChainlinkBTCOracle() public {
        ChainlinkPriceOracle chainlinkDeployedOracle = ChainlinkPriceOracle(0x2D403B4e2FEc4582BEc0F6002a803A3b962AC8a8);

        assertEq(
            address(chainlinkDeployedOracle.priceAggregator()), address(chainlinkPriceOracleBTC.priceAggregator())
        );
        assertEq(chainlinkDeployedOracle.timeout(), chainlinkPriceOracleBTC.timeout());
        assertEq(chainlinkDeployedOracle.DEVIATION(), chainlinkPriceOracleBTC.DEVIATION());
        assertEq(
            chainlinkDeployedOracle.MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND(),
            chainlinkPriceOracleBTC.MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND()
        );
    }
}
