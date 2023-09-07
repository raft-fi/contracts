// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PriceFeedTestnet } from "./mocks/PriceFeedTestnet.sol";
import { IRToken } from "../contracts/Interfaces/IRToken.sol";
import { IPositionManager } from "../contracts/Interfaces/IPositionManager.sol";
import {
    IInterestRatePositionManager,
    InterestRatePositionManager
} from "../contracts/InterestRates/InterestRatePositionManager.sol";
import { InterestRateDebtToken } from "../contracts/InterestRates/InterestRateDebtToken.sol";
import { ERC20Indexable } from "../contracts/ERC20Indexable.sol";
import { SplitLiquidationCollateral } from "../contracts/SplitLiquidationCollateral.sol";
import { IPSM } from "../contracts/PSM/IPSM.sol";
import { IChai } from "../contracts/PSM/IChai.sol";
import { ILock } from "../contracts/common/ILock.sol";
import { ChaiPSM } from "../contracts/PSM/ChaiPSM.sol";
import { ConstantPriceFeed } from "../contracts/common/ConstantPriceFeed.sol";
import { PSMFixedFee } from "../contracts/PSM/FixedFee.sol";
import { PSMSplitLiquidationCollateral } from "../contracts/common/PSMSplitLiquidationCollateral.sol";

contract InterestRatePositionManagerTests is Test {
    IRToken public constant R = IRToken(address(0x183015a9bA6fF60230fdEaDc3F43b3D788b13e21));
    address public constant OWNER = address(0xaB40A7e3cEF4AfB323cE23B6565012Ac7c76BFef);
    PriceFeedTestnet public wethPriceFeed;
    IERC20 public constant WETH = IERC20(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    InterestRatePositionManager public irPosman;
    uint256 public constant CAP = 3000e18;
    uint256 public constant INDEX_INC_PER_SEC = 1e10;

    function setUp() public {
        vm.createSelectFork("mainnet", 18_004_964);
        wethPriceFeed = new PriceFeedTestnet();
        wethPriceFeed.setPrice(1000e18);
        vm.startPrank(OWNER);
        irPosman = new InterestRatePositionManager(R);
        irPosman.positionManager().addCollateralToken(
            irPosman, new ConstantPriceFeed(address(irPosman)), new PSMSplitLiquidationCollateral()
        );
        irPosman.addCollateralToken(
            WETH,
            wethPriceFeed,
            new SplitLiquidationCollateral(),
            new ERC20Indexable(address(irPosman), "Raft WETH collateral", "rWETH-c", type(uint256).max),
            new InterestRateDebtToken(address(irPosman), "Raft WETH debt", "rWETH-d", WETH, CAP, INDEX_INC_PER_SEC)
        );
        vm.stopPrank();
    }

    function testMintFeesInvalidCaller() public {
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IInterestRatePositionManager.InvalidDebtToken.selector, OWNER));
        irPosman.mintFees(WETH, 1);
    }
}
