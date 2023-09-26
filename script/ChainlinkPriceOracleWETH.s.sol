// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Script } from "forge-std/Script.sol";
import { AggregatorV3Interface } from "@smartcontractkit/chainlink/interfaces/AggregatorV3Interface.sol";
import { ChainlinkPriceOracle } from "../contracts/Oracles/ChainlinkPriceOracle.sol";

contract ChainlinkPriceOracleWETH is Script {
    AggregatorV3Interface public constant aggregatorV3ETH =
        AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        new ChainlinkPriceOracle(aggregatorV3ETH, 0, 2 hours, 18, 15e16);

        vm.stopBroadcast();
    }
}
