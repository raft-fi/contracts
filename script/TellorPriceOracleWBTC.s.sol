// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Script } from "forge-std/Script.sol";
import { ITellor } from "../contracts/Dependencies/ITellor.sol";
import { TellorPriceOracle } from "../contracts/Oracles/TellorPriceOracle.sol";

contract TellorPriceOracleWBTC is Script {
    ITellor public constant tellorOracle = ITellor(0xD9157453E2668B2fc45b7A803D3FEF3642430cC0);

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        new TellorPriceOracle(
            tellorOracle, keccak256(abi.encode("SpotPrice", abi.encode("wbtc", "usd"))), 5e15, 3 hours, 28
        );

        vm.stopBroadcast();
    }
}
