// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Script } from "forge-std/Script.sol";
import { IWstETH } from "../contracts/Dependencies/IWstETH.sol";
import { PositionManager } from "../contracts/PositionManager.sol";
import { IERC20Wrapped, PositionManagerStETH } from "../contracts/PositionManagerStETH.sol";
import { SplitLiquidationCollateral } from "../contracts/SplitLiquidationCollateral.sol";
import { WrappedCollateralToken } from "../contracts/WrappedCollateralToken.sol";
import { PriceFeedTestnet } from "../test/mocks/PriceFeedTestnet.sol";

contract DeployScript is Script {
    address public constant WSTETH = 0x6320cD32aA674d2898A68ec82e869385Fc5f7E2f;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        PositionManager positionManager = new PositionManager();
        WrappedCollateralToken wrappedCollateralToken = new WrappedCollateralToken(
            IERC20(WSTETH), "Wrapped Collateral Token", "WCT", 100_000_0e18, type(uint256).max, address(positionManager)
        );
        new PositionManagerStETH(address(positionManager), IERC20Wrapped(address(wrappedCollateralToken)));

        PriceFeedTestnet priceFeed = new PriceFeedTestnet();
        SplitLiquidationCollateral splitLiquidationCollateral = new SplitLiquidationCollateral();
        positionManager.addCollateralToken(wrappedCollateralToken, priceFeed, splitLiquidationCollateral);

        vm.stopBroadcast();
    }
}
