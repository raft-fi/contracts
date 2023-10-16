// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Script } from "forge-std/Script.sol";
import { AggregatorV3Interface } from "@smartcontractkit/chainlink/interfaces/AggregatorV3Interface.sol";
import { IPriceFeed } from "../contracts/Interfaces/IPriceFeed.sol";
import { ChainlinkPriceOracleRETH } from "../contracts/Oracles/ChainlinkPriceOracleRETH.sol";

contract ChainlinkPriceOracleWBTC is Script {
    AggregatorV3Interface public constant aggregatorV3WBTC =
        AggregatorV3Interface(0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23);
    IPriceFeed public constant priceFeedBTC = IPriceFeed(0x0e6373a67e72666C8b044155c78E4178Fe2c893C);

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        new ChainlinkPriceOracleRETH(aggregatorV3WBTC, priceFeedBTC, 2e16, 27 hours, 28, 20e16);

        vm.stopBroadcast();
    }
}
