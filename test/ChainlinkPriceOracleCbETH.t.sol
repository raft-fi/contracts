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

contract ChainlinkPriceOracleCbETHTest is Test {
    AggregatorV3Interface public constant aggregatorV3CbETH =
        AggregatorV3Interface(0xF017fcB346A1885194689bA23Eff2fE6fA5C483b);
    ChainlinkPriceOracleRETH public chainlinkPriceOracleCbETH;

    function setUp() public {
        vm.createSelectFork("mainnet", 18_168_971);

        chainlinkPriceOracleCbETH = new ChainlinkPriceOracleRETH(
            aggregatorV3CbETH, IPriceFeed(0xE66bC214beef3D61Ce66dA9f80E67E14413bfc5A), 1e16, 27 hours, 18, 2e17);
    }

    function testChainlinkCbETHPrice() public {
        vm.warp(1_695_114_551);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse =
            chainlinkPriceOracleCbETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, false);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertApproxEqAbs(priceOracleResponse.price, 1_718_217e15, 1e15);
    }

    function testCheckDeployedChainlinkCbETHOracle() public {
        ChainlinkPriceOracleRETH chainlinkDeplyedOracle =
            ChainlinkPriceOracleRETH(0xCeb62B7080460c5C5E91B7acFC490bB49ea34Df6);

        assertEq(
            address(chainlinkDeplyedOracle.priceAggregator()), address(chainlinkPriceOracleCbETH.priceAggregator())
        );
        assertEq(address(chainlinkDeplyedOracle.priceFeedETH()), address(chainlinkPriceOracleCbETH.priceFeedETH()));
        assertEq(chainlinkDeplyedOracle.timeout(), chainlinkPriceOracleCbETH.timeout());
        assertEq(chainlinkDeplyedOracle.DEVIATION(), chainlinkPriceOracleCbETH.DEVIATION());
        assertEq(
            chainlinkDeplyedOracle.MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND(),
            chainlinkPriceOracleCbETH.MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND()
        );
    }
}
