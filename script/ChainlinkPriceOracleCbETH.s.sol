// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Script } from "forge-std/Script.sol";
import { AggregatorV3Interface } from "@smartcontractkit/chainlink/interfaces/AggregatorV3Interface.sol";
import { ChainlinkPriceOracle } from "../contracts/Oracles/ChainlinkPriceOracle.sol";

contract ChainlinkPriceOracleCbETH is Script {
    AggregatorV3Interface public constant aggregatorV3CbETH =
        AggregatorV3Interface(0xF017fcB346A1885194689bA23Eff2fE6fA5C483b);

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        new ChainlinkPriceOracle(aggregatorV3CbETH, 0, 26 hours, 18, 10e16);

        vm.stopBroadcast();
    }
}
