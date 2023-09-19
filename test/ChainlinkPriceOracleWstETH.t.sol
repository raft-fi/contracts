// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { AggregatorV3Interface } from "@smartcontractkit/chainlink/interfaces/AggregatorV3Interface.sol";
import { IWstETH } from "../contracts/Dependencies/IWstETH.sol";
import { IChainlinkPriceOracle } from "../contracts/Oracles/Interfaces/IChainlinkPriceOracle.sol";
import { IPriceOracle } from "../contracts/Oracles/Interfaces/IPriceOracle.sol";
import { ChainlinkPriceOracleWstETH } from "../contracts/Oracles/ChainlinkPriceOracleWstETH.sol";

interface IChainlinkPriceOracleOld {
    function TIMEOUT() external view returns (uint256);
}

contract ChainlinkPriceOracleWstETHTest is Test {
    AggregatorV3Interface public constant aggregatorV3StETH =
        AggregatorV3Interface(0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8);
    IWstETH public constant wstETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ChainlinkPriceOracleWstETH public chainlinkPriceOracleWstETH;

    function setUp() public {
        vm.createSelectFork("mainnet", 17_318_021);

        chainlinkPriceOracleWstETH =
            new ChainlinkPriceOracleWstETH(aggregatorV3StETH, wstETH, 1e16, 3 hours, 18, 25e16);
    }

    function testChainlinkWstETHPrice() public {
        vm.warp(1_684_797_155);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse =
            chainlinkPriceOracleWstETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, false);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertApproxEqAbs(priceOracleResponse.price, 2_047_762e15, 1e15);
    }

    function testCheckDeployedChainlinkWstETHOracle() public {
        IChainlinkPriceOracle chainlinkDeployedOracle =
            IChainlinkPriceOracle(0x36f4a2E3BA37F438C902FD3389e5b60d0904310A);

        assertEq(
            address(chainlinkDeployedOracle.priceAggregator()), address(chainlinkPriceOracleWstETH.priceAggregator())
        );
        assertEq(
            IChainlinkPriceOracleOld(address(chainlinkDeployedOracle)).TIMEOUT(), chainlinkPriceOracleWstETH.timeout()
        );
        assertEq(chainlinkDeployedOracle.DEVIATION(), chainlinkPriceOracleWstETH.DEVIATION());
        assertEq(
            chainlinkDeployedOracle.MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND(),
            chainlinkPriceOracleWstETH.MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND()
        );
    }
}
