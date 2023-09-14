// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Script } from "forge-std/Script.sol";
import { IERC3156FlashLender } from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UpperPegArbitrager } from "../contracts/PSM/UpperPegArbitrager.sol";
import { IPSM } from "../contracts/PSM/IPSM.sol";

contract DeployUpperPegArbitrager is Script {
    IERC3156FlashLender public constant LENDER = IERC3156FlashLender(0x60744434d6339a6B27d73d9Eda62b6F66a0a04FA);
    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IPSM public constant CHAI_PSM = IPSM(0xa03342feB2e1D4690B60Ef556509ec3B76c97eE7);
    address public constant AGGREGATION_ROUTER_V5 = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    address public constant NEW_OWNER = 0xf41f9fC0B622Eb112445fD7b32fc5190d0c0D3f4;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        UpperPegArbitrager upperPegArbitrager = new UpperPegArbitrager(LENDER, DAI, CHAI_PSM, AGGREGATION_ROUTER_V5);
        upperPegArbitrager.transferOwnership(NEW_OWNER);

        vm.stopBroadcast();
    }
}
