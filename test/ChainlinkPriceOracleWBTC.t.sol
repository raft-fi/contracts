// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { AggregatorV3Interface } from "@smartcontractkit/chainlink/interfaces/AggregatorV3Interface.sol";
import { ITellor } from "../contracts/Dependencies/ITellor.sol";
import { IPriceOracle } from "../contracts/Oracles/Interfaces/IPriceOracle.sol";
import { ChainlinkPriceOracle } from "../contracts/Oracles/ChainlinkPriceOracle.sol";
import { ChainlinkPriceOracleRETH } from "../contracts/Oracles/ChainlinkPriceOracleRETH.sol";
import { TellorPriceOracle } from "../contracts/Oracles/TellorPriceOracle.sol";
import { PriceFeed } from "../contracts/PriceFeed.sol";

contract ChainlinkPriceOracleWBTC is Test {
    AggregatorV3Interface public constant AGGREGATOR_V3_BTC =
        AggregatorV3Interface(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);
    AggregatorV3Interface public constant AGGREGATOR_V3_WBTC =
        AggregatorV3Interface(0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23);
    ChainlinkPriceOracleRETH public chainlinkPriceOracleWBTC;

    function setUp() public {
        vm.createSelectFork("mainnet", 17_509_100);

        ChainlinkPriceOracle chainlinkPriceOracleBTC =
            new ChainlinkPriceOracle(AGGREGATOR_V3_BTC, 5e15, 3 hours, 18, 25e16);
        ITellor tellorOracle = ITellor(0xD9157453E2668B2fc45b7A803D3FEF3642430cC0);
        TellorPriceOracle tellorPriceOracleBTC = new TellorPriceOracle(
            tellorOracle, keccak256(abi.encode("SpotPrice", abi.encode("btc", "usd"))), 0, 3 hours, 18);
        PriceFeed priceFeedBTC = new PriceFeed(chainlinkPriceOracleBTC, tellorPriceOracleBTC, 5e16);

        chainlinkPriceOracleWBTC =
            new ChainlinkPriceOracleRETH(AGGREGATOR_V3_WBTC, priceFeedBTC, 2e16, 27 hours, 28, 25e16);
    }

    function testChainlinkWBTCHPrice() public {
        vm.warp(1_687_122_910);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = chainlinkPriceOracleWBTC.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, false);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertApproxEqAbs(priceOracleResponse.price, 26_501e28, 1e28);
    }
}
