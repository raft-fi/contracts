// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { AggregatorV3Interface } from "@smartcontractkit/chainlink/interfaces/AggregatorV3Interface.sol";
import { ITellor } from "../contracts/Dependencies/ITellor.sol";
import { IPriceFeed } from "../contracts/Interfaces/IPriceFeed.sol";
import { IPriceOracle } from "../contracts/Oracles/Interfaces/IPriceOracle.sol";
import { ChainlinkPriceOracle } from "../contracts/Oracles/ChainlinkPriceOracle.sol";
import { ChainlinkPriceOracleRETH } from "../contracts/Oracles/ChainlinkPriceOracleRETH.sol";
import { TellorPriceOracle } from "../contracts/Oracles/TellorPriceOracle.sol";
import { PriceFeed } from "../contracts/PriceFeed.sol";

contract ChainlinkPriceOracleRETHTest is Test {
    AggregatorV3Interface public constant aggregatorV3RETH =
        AggregatorV3Interface(0x536218f9E9Eb48863970252233c8F271f554C2d0);
    ChainlinkPriceOracleRETH public chainlinkPriceOracleRETH;

    function setUp() public {
        vm.createSelectFork("mainnet", 18_168_961);

        chainlinkPriceOracleRETH = new ChainlinkPriceOracleRETH(
            aggregatorV3RETH, IPriceFeed(0xE66bC214beef3D61Ce66dA9f80E67E14413bfc5A), 2e16, 27 hours, 18, 2e17);
    }

    function testChainlinkRETHPrice() public {
        vm.warp(1_695_114_431);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = chainlinkPriceOracleRETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, false);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertApproxEqAbs(priceOracleResponse.price, 1_779_017e15, 1e15);
    }

    function testCheckDeployedChainlinkRETHOracle() public {
        ChainlinkPriceOracleRETH chainlinkDeplyedOracle =
            ChainlinkPriceOracleRETH(0x3b4bCb14f31Fb4Ee5C1d3E07e4d623FEf50F122E);

        assertEq(
            address(chainlinkDeplyedOracle.priceAggregator()), address(chainlinkPriceOracleRETH.priceAggregator())
        );
        assertEq(address(chainlinkDeplyedOracle.priceFeedETH()), address(chainlinkPriceOracleRETH.priceFeedETH()));
        assertEq(chainlinkDeplyedOracle.timeout(), chainlinkPriceOracleRETH.timeout());
        assertEq(chainlinkDeplyedOracle.DEVIATION(), chainlinkPriceOracleRETH.DEVIATION());
        assertEq(
            chainlinkDeplyedOracle.MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND(),
            chainlinkPriceOracleRETH.MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND()
        );
    }
}
