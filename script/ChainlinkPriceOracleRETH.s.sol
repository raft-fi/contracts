// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Script } from "forge-std/Script.sol";
import { AggregatorV3Interface } from "@smartcontractkit/chainlink/interfaces/AggregatorV3Interface.sol";
import { ChainlinkPriceOracle } from "../contracts/Oracles/ChainlinkPriceOracle.sol";

contract ChainlinkPriceOracleRETH is Script {
    AggregatorV3Interface public constant aggregatorV3RETH =
        AggregatorV3Interface(0x536218f9E9Eb48863970252233c8F271f554C2d0);

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        new ChainlinkPriceOracle(aggregatorV3RETH, 0, 26 hours, 18, 10e16);

        vm.stopBroadcast();
    }
}
