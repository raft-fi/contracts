// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Script } from "forge-std/Script.sol";
import { IWstETH } from "../contracts/Dependencies/IWstETH.sol";
import { ChainlinkPriceOracleReporter } from "../contracts/Oracles/ChainlinkPriceOracleReporter.sol";
import { MockChainlink } from "../test/mocks/MockChainlink.sol";

contract DeployPriceOracleReporterScript is Script {
    IWstETH public constant WSTETH = IWstETH(address(0x6320cD32aA674d2898A68ec82e869385Fc5f7E2f));

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        MockChainlink mockChainlink = new MockChainlink();

        new ChainlinkPriceOracleReporter(mockChainlink, WSTETH);

        vm.stopBroadcast();
    }
}
