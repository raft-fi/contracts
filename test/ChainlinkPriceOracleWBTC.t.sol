// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { AggregatorV3Interface } from "@smartcontractkit/chainlink/interfaces/AggregatorV3Interface.sol";
import { IPriceFeed } from "../contracts/Interfaces/IPriceFeed.sol";
import { IPriceOracle } from "../contracts/Oracles/Interfaces/IPriceOracle.sol";
import { ChainlinkPriceOracleRETH } from "../contracts/Oracles/ChainlinkPriceOracleRETH.sol";

contract ChainlinkPriceOracleWBTC is Test {
    AggregatorV3Interface public constant AGGREGATOR_V3_BTC =
        AggregatorV3Interface(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);
    AggregatorV3Interface public constant AGGREGATOR_V3_WBTC =
        AggregatorV3Interface(0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23);
    IPriceFeed public constant priceFeedBTC = IPriceFeed(0x0e6373a67e72666C8b044155c78E4178Fe2c893C);
    ChainlinkPriceOracleRETH public chainlinkPriceOracleWBTC;

    function setUp() public {
        vm.createSelectFork("mainnet", 18_363_119);

        chainlinkPriceOracleWBTC =
            new ChainlinkPriceOracleRETH(AGGREGATOR_V3_WBTC, priceFeedBTC, 2e16, 27 hours, 28, 20e16);
    }

    function testChainlinkWBTCHPrice() public {
        vm.warp(1_697_461_521);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = chainlinkPriceOracleWBTC.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, false);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertApproxEqAbs(priceOracleResponse.price, 27_861e28, 1e28);
    }

    function testCheckDeployedChainlinkWBTCOracle() public {
        ChainlinkPriceOracleRETH chainlinkDeployedOracle =
            ChainlinkPriceOracleRETH(0x4e3Bd45C70D2e62f75c76D6167897374832400FF);

        assertEq(
            address(chainlinkDeployedOracle.priceAggregator()), address(chainlinkPriceOracleWBTC.priceAggregator())
        );
        assertEq(address(chainlinkDeployedOracle.priceFeedETH()), address(chainlinkPriceOracleWBTC.priceFeedETH()));
        assertEq(chainlinkDeployedOracle.timeout(), chainlinkPriceOracleWBTC.timeout());
        assertEq(chainlinkDeployedOracle.DEVIATION(), chainlinkPriceOracleWBTC.DEVIATION());
        assertEq(
            chainlinkDeployedOracle.MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND(),
            chainlinkPriceOracleWBTC.MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND()
        );
        assertEq(chainlinkDeployedOracle.targetDigits(), chainlinkPriceOracleWBTC.targetDigits());
    }
}
