// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Script } from "forge-std/Script.sol";
import { AggregatorV3Interface } from "@smartcontractkit/chainlink/interfaces/AggregatorV3Interface.sol";
import { ChainlinkPriceOracle } from "../contracts/Oracles/ChainlinkPriceOracle.sol";

contract ChainlinkPriceOracleSwETH is Script {
    AggregatorV3Interface public constant aggregatorV3SwETH =
        AggregatorV3Interface(0x0704eEc81ea7CF98Aa4A400c65DC4ED5933bddf7);

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        new ChainlinkPriceOracle(aggregatorV3SwETH, 0, 8 hours, 18, 15e16);

        vm.stopBroadcast();
    }
}
