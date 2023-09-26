// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { AggregatorV3Interface } from "@smartcontractkit/chainlink/interfaces/AggregatorV3Interface.sol";
import { IPriceOracle } from "../contracts/Oracles/Interfaces/IPriceOracle.sol";
import { IChainlinkPriceOracle } from "../contracts/Oracles/Interfaces/IChainlinkPriceOracle.sol";
import { ChainlinkPriceOracle } from "../contracts/Oracles/ChainlinkPriceOracle.sol";

contract ChainlinkPriceOracleWETHTest is Test {
    AggregatorV3Interface public constant aggregatorV3ETH =
        AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    IChainlinkPriceOracle public chainlinkPriceOracleWETH;

    function setUp() public {
        vm.createSelectFork("mainnet", 18_127_055);

        chainlinkPriceOracleWETH = new ChainlinkPriceOracle(aggregatorV3ETH, 5e15, 3 hours, 18, 25e16);
    }

    function testChainlinkWETHPrice() public {
        vm.warp(1_694_604_083);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = chainlinkPriceOracleWETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, false);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertApproxEqAbs(priceOracleResponse.price, 1_598_700e15, 1e15);
    }

    function testCheckDeployedChainlinkWETHOracle() public {
        IChainlinkPriceOracle chainlinkDeployedOracle =
            IChainlinkPriceOracle(0xea589074765677892191E796208165E97F7384b2);

        assertEq(
            address(chainlinkDeployedOracle.priceAggregator()), address(chainlinkPriceOracleWETH.priceAggregator())
        );
        assertEq(chainlinkDeployedOracle.timeout(), chainlinkPriceOracleWETH.timeout());
        assertEq(chainlinkDeployedOracle.DEVIATION(), chainlinkPriceOracleWETH.DEVIATION());
        assertEq(
            chainlinkDeployedOracle.MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND(),
            chainlinkPriceOracleWETH.MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND()
        );
    }
}
