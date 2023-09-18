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

contract ChainlinkPriceOracleRETHTest is Test {
    AggregatorV3Interface public constant aggregatorV3ETH =
        AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    AggregatorV3Interface public constant aggregatorV3RETH =
        AggregatorV3Interface(0x536218f9E9Eb48863970252233c8F271f554C2d0);
    ChainlinkPriceOracleRETH public chainlinkPriceOracleRETH;

    function setUp() public {
        vm.createSelectFork("mainnet", 17_509_100);

        ChainlinkPriceOracle chainlinkPriceOracleETH =
            new ChainlinkPriceOracle(aggregatorV3ETH, 5e15, 1 hours, 18, 25e16);
        ITellor tellorOracle = ITellor(0xD9157453E2668B2fc45b7A803D3FEF3642430cC0);
        TellorPriceOracle tellorPriceOracleETH = new TellorPriceOracle(
            tellorOracle, keccak256(abi.encode("SpotPrice", abi.encode("eth", "usd"))), 0, 1 hours, 18);
        PriceFeed priceFeedETH = new PriceFeed(chainlinkPriceOracleETH, tellorPriceOracleETH, 5e16);

        chainlinkPriceOracleRETH =
            new ChainlinkPriceOracleRETH(aggregatorV3RETH, priceFeedETH, 25e15, 48 hours, 18, 25e16);
    }

    function testChainlinkRETHPrice() public {
        vm.warp(1_687_122_910);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = chainlinkPriceOracleRETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, false);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertApproxEqAbs(priceOracleResponse.price, 1_857_511e15, 1e15);
    }
}
