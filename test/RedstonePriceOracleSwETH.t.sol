// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { AggregatorV3Interface } from "@smartcontractkit/chainlink/interfaces/AggregatorV3Interface.sol";
import { IChainlinkPriceOracle } from "../contracts/Oracles/Interfaces/IChainlinkPriceOracle.sol";
import { IPriceOracle } from "../contracts/Oracles/Interfaces/IPriceOracle.sol";
import { ChainlinkPriceOracle } from "../contracts/Oracles/ChainlinkPriceOracle.sol";

contract RedstonePriceOracleSwETHTest is Test {
    AggregatorV3Interface public constant aggregatorV3SwETH =
        AggregatorV3Interface(0x0704eEc81ea7CF98Aa4A400c65DC4ED5933bddf7);
    ChainlinkPriceOracle public redstonePriceOracleSwETH;

    function setUp() public {
        vm.createSelectFork("mainnet", 18_127_754);

        redstonePriceOracleSwETH = new ChainlinkPriceOracle(aggregatorV3SwETH, 5e15, 9 hours, 18, 25e16);
    }

    function testRedstonekSwETHPrice() public {
        vm.warp(1_694_612_615);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = redstonePriceOracleSwETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, false);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertApproxEqAbs(priceOracleResponse.price, 1_637_250e15, 1e15);
    }

    function testCheckDeployedRedstoneSwETHOracle() public {
        IChainlinkPriceOracle redstoneDeployedOracle =
            IChainlinkPriceOracle(0xecB97207D588F334d7D06b99Acf9d85C11A47732);

        assertEq(
            address(redstoneDeployedOracle.priceAggregator()), address(redstonePriceOracleSwETH.priceAggregator())
        );
        assertEq(redstoneDeployedOracle.timeout(), redstonePriceOracleSwETH.timeout());
        /* TODO It is wrong setup in the deployed contract, but, it is not important because it is not used
                    (redemCollateral is it not used for V2 vaults)
        assertEq(redstoneDeployedOracle.DEVIATION(), redstonePriceOracleSwETH.DEVIATION());
        */
        assertEq(
            redstoneDeployedOracle.MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND(),
            redstonePriceOracleSwETH.MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND()
        );
    }
}
