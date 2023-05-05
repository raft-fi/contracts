// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Script } from "forge-std/Script.sol";
import { IWstETH } from "../contracts/Dependencies/IWstETH.sol";
import { PositionManager } from "../contracts/PositionManager.sol";
import { PositionManagerStETH } from "../contracts/PositionManagerStETH.sol";
import { SplitLiquidationCollateral } from "../contracts/SplitLiquidationCollateral.sol";
import { PriceFeedTestnet } from "../test/mocks/PriceFeedTestnet.sol";

contract DeployScript is Script {
    IWstETH public constant WSTETH = IWstETH(address(0x6320cD32aA674d2898A68ec82e869385Fc5f7E2f));

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        SplitLiquidationCollateral splitLiquidationCollateral = new SplitLiquidationCollateral();
        PositionManager positionManager = new PositionManager(splitLiquidationCollateral);
        new PositionManagerStETH(address(positionManager), WSTETH);

        PriceFeedTestnet priceFeed = new PriceFeedTestnet();
        positionManager.addCollateralToken(WSTETH, priceFeed);

        vm.stopBroadcast();
    }
}
