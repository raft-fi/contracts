// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { AggregatorV3Interface } from "@smartcontractkit/chainlink/interfaces/AggregatorV3Interface.sol";
import { IPriceOracle } from "../contracts/Oracles/Interfaces/IPriceOracle.sol";
import { ChainlinkPriceOracle } from "../contracts/Oracles/ChainlinkPriceOracle.sol";

contract RedstonePriceOracleSwETHTest is Test {
    AggregatorV3Interface public constant aggregatorV3SwETH =
        AggregatorV3Interface(0x0704eEc81ea7CF98Aa4A400c65DC4ED5933bddf7);
    ChainlinkPriceOracle public redstonePriceOracleSwETH;

    function setUp() public {
        vm.createSelectFork("mainnet", 18_001_216);

        redstonePriceOracleSwETH = new ChainlinkPriceOracle(aggregatorV3SwETH, 5e15, 9 hours);
    }

    function testRedstonekSwETHPrice() public {
        vm.warp(1_693_082_387);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = redstonePriceOracleSwETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, false);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertApproxEqAbs(priceOracleResponse.price, 1_683_118e15, 1e15);
    }
}
