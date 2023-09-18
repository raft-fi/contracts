// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { PriceFeedTestnet } from "./mocks/PriceFeedTestnet.sol";
import { IRToken } from "../contracts/Interfaces/IRToken.sol";
import {
    IInterestRatePositionManager,
    InterestRatePositionManager
} from "../contracts/InterestRates/InterestRatePositionManager.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { InterestRateDebtToken } from "../contracts/InterestRates/InterestRateDebtToken.sol";
import { IPositionManager } from "../contracts/Interfaces/IPositionManager.sol";
import { IERC20Indexable } from "../contracts/Interfaces/IERC20Indexable.sol";
import { ERC20Indexable } from "../contracts/ERC20Indexable.sol";
import { SplitLiquidationCollateral } from "../contracts/SplitLiquidationCollateral.sol";
import { ConstantPriceFeed } from "../contracts/common/ConstantPriceFeed.sol";
import { PSMSplitLiquidationCollateral } from "../contracts/common/PSMSplitLiquidationCollateral.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";

contract PositionManagerWBTCTest is Test {
    IRToken public constant R = IRToken(address(0x183015a9bA6fF60230fdEaDc3F43b3D788b13e21));
    address public constant OWNER = address(0xaB40A7e3cEF4AfB323cE23B6565012Ac7c76BFef);
    // User accounts
    address public constant ALICE = address(1);
    address public constant BOB = address(2);
    // WBTC
    PriceFeedTestnet public wbtcPriceFeed;
    IERC20 public constant WBTC = IERC20(address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599));

    InterestRatePositionManager public irPosman;
    uint256 public constant CAP = 300_000e18;
    uint256 public constant INDEX_INC_PER_SEC = 1e10;
    address public constant WBTC_WHALE = address(0x7f62f9592b823331E012D3c5DdF2A7714CfB9de2);
    address public constant R_WHALE = address(0x5EC6abfF9BB4c673f63D077a962A29945f744857);

    function setUp() public {
        vm.createSelectFork("mainnet", 18_004_964);
        wbtcPriceFeed = new PriceFeedTestnet();
        wbtcPriceFeed.setPrice(25_000e28);
        vm.startPrank(OWNER);
        irPosman = new InterestRatePositionManager(R);
        irPosman.positionManager().addCollateralToken(
            irPosman, new ConstantPriceFeed(address(irPosman)), new PSMSplitLiquidationCollateral()
        );

        irPosman.addCollateralToken(
            WBTC,
            wbtcPriceFeed,
            new SplitLiquidationCollateral(),
            new ERC20Indexable(address(irPosman), "Raft WBTC collateral", "rWBTC-c", type(uint256).max),
            new InterestRateDebtToken(
                address(irPosman), "Raft WBTC debt", "rWBTC-d", WBTC, CAP, INDEX_INC_PER_SEC
            )
        );
        vm.stopPrank();

        vm.startPrank(WBTC_WHALE);
        WBTC.transfer(ALICE, 10e8);
        WBTC.transfer(BOB, 10e8);
        vm.stopPrank();
    }

    function testSuccessfulOpenPosition() public {
        // Alice transaction
        vm.startPrank(ALICE);
        uint256 aliceCollateralAmount = 5e8;
        uint256 aliceDebtAmount = 62_500e18;
        WBTC.approve(address(irPosman), aliceCollateralAmount);
        ERC20PermitSignature memory emptySignature;
        irPosman.managePosition(WBTC, ALICE, aliceCollateralAmount, true, aliceDebtAmount, true, 0, emptySignature);
        // Alice checks
        (IERC20Indexable wBTCCollateralToken, IERC20Indexable wBTCDebtToken,,,,,,,,) = irPosman.collateralInfo(WBTC);
        assertEq(wBTCDebtToken.currentIndex(), 1e18);
        assertEq(wBTCDebtToken.balanceOf(ALICE), aliceDebtAmount);
        assertEq(wBTCCollateralToken.currentIndex(), 1e18);
        assertEq(wBTCCollateralToken.balanceOf(ALICE), aliceCollateralAmount);
        assertEq(R.balanceOf(ALICE), aliceDebtAmount);
        uint256 currentAliceICR = PositionManagerUtils.getCurrentICR(irPosman, WBTC, ALICE, wbtcPriceFeed.getPrice());
        assertEq(currentAliceICR, 2e18);
        vm.stopPrank();
    }

    function testCannotOpenPosition() public {
        // Alice transaction
        vm.startPrank(ALICE);
        uint256 aliceCollateralAmount = 5e8;
        uint256 aliceDebtAmount = 125_000e18;
        WBTC.approve(address(irPosman), aliceCollateralAmount);
        ERC20PermitSignature memory emptySignature;
        vm.expectRevert(abi.encodeWithSelector(IPositionManager.NewICRLowerThanMCR.selector, MathUtils._100_PERCENT));
        irPosman.managePosition(WBTC, ALICE, aliceCollateralAmount, true, aliceDebtAmount, true, 0, emptySignature);
    }

    function testSuccessfulClosePosition() public {
        // Alice transaction for open position
        vm.startPrank(ALICE);
        uint256 aliceCollateralAmount = 5e8;
        uint256 aliceDebtAmount = 62_500e18;
        WBTC.approve(address(irPosman), aliceCollateralAmount);
        ERC20PermitSignature memory emptySignature;
        irPosman.managePosition(WBTC, ALICE, aliceCollateralAmount, true, aliceDebtAmount, true, 0, emptySignature);
        vm.stopPrank();

        // Bob transaction for open position
        vm.startPrank(BOB);
        uint256 bobCollateralAmount = 5e8;
        uint256 bobDebtAmount = 12_500e18;
        WBTC.approve(address(irPosman), bobCollateralAmount);
        irPosman.managePosition(WBTC, BOB, bobCollateralAmount, true, bobDebtAmount, true, 0, emptySignature);
        vm.stopPrank();

        // Alice transaction for close position
        vm.startPrank(ALICE);
        uint256 rTotalSupplyBefore = R.totalSupply();
        uint256 aliceWBTCBalanceBefore = WBTC.balanceOf(ALICE);
        R.approve(address(irPosman), aliceDebtAmount);
        irPosman.managePosition(WBTC, ALICE, 0, false, type(uint256).max, false, 0, emptySignature);
        // Alice checks
        (IERC20Indexable wBTCCollateralToken, IERC20Indexable wBTCDebtToken,,,,,,,,) = irPosman.collateralInfo(WBTC);
        assertEq(wBTCDebtToken.currentIndex(), 1e18);
        assertEq(wBTCDebtToken.balanceOf(ALICE), 0);
        assertEq(wBTCDebtToken.totalSupply(), bobDebtAmount);
        assertEq(wBTCCollateralToken.currentIndex(), 1e18);
        assertEq(wBTCCollateralToken.balanceOf(ALICE), 0);
        assertEq(wBTCCollateralToken.totalSupply(), bobCollateralAmount);
        assertEq(R.balanceOf(ALICE), 0);
        assertEq(R.totalSupply(), rTotalSupplyBefore - aliceDebtAmount);
        assertEq(WBTC.balanceOf(ALICE), aliceWBTCBalanceBefore + aliceCollateralAmount);
        uint256 currentAliceICR = PositionManagerUtils.getCurrentICR(irPosman, WBTC, ALICE, wbtcPriceFeed.getPrice());
        assertEq(currentAliceICR, type(uint256).max);
        vm.stopPrank();
    }

    function testSuccessfulLiquidation() public {
        vm.startPrank(ALICE);
        uint256 aliceCollateralAmount = 5e8;
        uint256 aliceDebtAmount = 62_500e18;
        WBTC.approve(address(irPosman), aliceCollateralAmount);
        ERC20PermitSignature memory emptySignature;
        irPosman.managePosition(WBTC, ALICE, aliceCollateralAmount, true, aliceDebtAmount, true, 0, emptySignature);
        vm.stopPrank();

        vm.startPrank(BOB);
        uint256 bobCollateralAmount = 5e8;
        uint256 bobDebtAmount = 12_500e18;
        WBTC.approve(address(irPosman), bobCollateralAmount);
        irPosman.managePosition(WBTC, BOB, bobCollateralAmount, true, bobDebtAmount, true, 0, emptySignature);
        vm.stopPrank();

        wbtcPriceFeed.setPrice(13_000e28);
        uint256 currentAliceICR = PositionManagerUtils.getCurrentICR(irPosman, WBTC, ALICE, wbtcPriceFeed.getPrice());
        assertEq(currentAliceICR, 104e16); // Ready for liquidation

        vm.startPrank(address(R_WHALE));
        R.transfer(address(this), aliceDebtAmount);
        vm.stopPrank();

        R.approve(address(irPosman), aliceDebtAmount);
        irPosman.liquidate(ALICE);

        (IERC20Indexable wBTCCollateralToken, IERC20Indexable wBTCDebtToken,,,,,,,,) = irPosman.collateralInfo(WBTC);
        assertEq(wBTCCollateralToken.currentIndex(), 1e18);
        assertEq(wBTCCollateralToken.balanceOf(ALICE), 0);
        assertEq(wBTCDebtToken.currentIndex(), 1e18);
        assertEq(wBTCDebtToken.balanceOf(ALICE), 0);
        assertEq(wBTCCollateralToken.balanceOf(BOB), bobCollateralAmount);
        assertEq(wBTCDebtToken.balanceOf(BOB), bobDebtAmount);
        assertEq(wBTCCollateralToken.totalSupply(), bobCollateralAmount);
        assertEq(WBTC.balanceOf(address(this)), aliceCollateralAmount);
        assertEq(R.balanceOf(address(this)), 0);
    }

    function testSuccessfulRedistributionWithLowTotalCollateralValue() public {
        vm.startPrank(ALICE);
        uint256 aliceCollateralAmount = 2e7; // 0.2 WBTC, 0.2 * 25_000 = 5_000 USD
        uint256 aliceDebtAmount = 4000e18;
        WBTC.approve(address(irPosman), aliceCollateralAmount);
        ERC20PermitSignature memory emptySignature;
        irPosman.managePosition(WBTC, ALICE, aliceCollateralAmount, true, aliceDebtAmount, true, 0, emptySignature);
        vm.stopPrank();

        vm.startPrank(BOB);
        uint256 bobCollateralAmount = 5e8;
        uint256 bobDebtAmount = 12_500e18;
        WBTC.approve(address(irPosman), bobCollateralAmount);
        irPosman.managePosition(WBTC, BOB, bobCollateralAmount, true, bobDebtAmount, true, 0, emptySignature);
        vm.stopPrank();

        wbtcPriceFeed.setPrice(12_500e28);
        uint256 currentAliceICR = PositionManagerUtils.getCurrentICR(irPosman, WBTC, ALICE, wbtcPriceFeed.getPrice());
        assertEq(currentAliceICR, 625e15); // Ready for redistribution
        uint256 bobICRBeforeRedistribution =
            PositionManagerUtils.getCurrentICR(irPosman, WBTC, BOB, wbtcPriceFeed.getPrice());

        vm.startPrank(address(R_WHALE));
        R.transfer(address(this), aliceDebtAmount);
        vm.stopPrank();

        irPosman.liquidate(ALICE);

        (IERC20Indexable wBTCCollateralToken, IERC20Indexable wBTCDebtToken,,,,,,,,) = irPosman.collateralInfo(WBTC);
        assertEq(wBTCCollateralToken.currentIndex(), 1_038_800_000_000_000_000);
        assertEq(wBTCCollateralToken.balanceOf(ALICE), 0);
        assertEq(wBTCDebtToken.currentIndex(), 1_320_000_000_000_000_000);
        assertEq(wBTCDebtToken.balanceOf(ALICE), 0);
        assertEq(wBTCCollateralToken.balanceOf(BOB), 519_400_000);
        assertEq(wBTCDebtToken.balanceOf(BOB), bobDebtAmount + aliceDebtAmount);
        assertEq(wBTCCollateralToken.totalSupply(), 519_400_000);
        assertEq(WBTC.balanceOf(address(this)), 600_000);
        assertEq(R.balanceOf(address(this)), aliceDebtAmount);
        assertLt(
            PositionManagerUtils.getCurrentICR(irPosman, WBTC, BOB, wbtcPriceFeed.getPrice()),
            bobICRBeforeRedistribution
        );
    }

    function testSuccessfulRedistributionWithMediumTotalCollateralValue() public {
        vm.startPrank(ALICE);
        uint256 aliceCollateralAmount = 5e8;
        uint256 aliceDebtAmount = 62_500e18;
        WBTC.approve(address(irPosman), aliceCollateralAmount);
        ERC20PermitSignature memory emptySignature;
        irPosman.managePosition(WBTC, ALICE, aliceCollateralAmount, true, aliceDebtAmount, true, 0, emptySignature);
        vm.stopPrank();

        vm.startPrank(BOB);
        uint256 bobCollateralAmount = 5e8;
        uint256 bobDebtAmount = 12_500e18;
        WBTC.approve(address(irPosman), bobCollateralAmount);
        irPosman.managePosition(WBTC, BOB, bobCollateralAmount, true, bobDebtAmount, true, 0, emptySignature);
        vm.stopPrank();

        wbtcPriceFeed.setPrice(12_000e28);
        uint256 currentAliceICR = PositionManagerUtils.getCurrentICR(irPosman, WBTC, ALICE, wbtcPriceFeed.getPrice());
        assertEq(currentAliceICR, 96e16); // Ready for redistribution
        uint256 bobICRBeforeRedistribution =
            PositionManagerUtils.getCurrentICR(irPosman, WBTC, BOB, wbtcPriceFeed.getPrice());

        vm.startPrank(address(R_WHALE));
        R.transfer(address(this), aliceDebtAmount);
        vm.stopPrank();

        irPosman.liquidate(ALICE);

        (IERC20Indexable wBTCCollateralToken, IERC20Indexable wBTCDebtToken,,,,,,,,) = irPosman.collateralInfo(WBTC);
        assertEq(wBTCCollateralToken.currentIndex(), 1_980_283_506_000_000_000);
        assertEq(wBTCCollateralToken.balanceOf(ALICE), 0);
        assertEq(wBTCDebtToken.currentIndex(), 6e18);
        assertEq(wBTCDebtToken.balanceOf(ALICE), 0);
        assertEq(wBTCCollateralToken.balanceOf(BOB), 990_141_753);
        assertEq(wBTCDebtToken.balanceOf(BOB), bobDebtAmount + aliceDebtAmount);
        assertEq(wBTCCollateralToken.totalSupply(), 990_141_753);
        assertEq(WBTC.balanceOf(address(this)), 9_858_247);
        assertEq(R.balanceOf(address(this)), aliceDebtAmount);
        assertLt(
            PositionManagerUtils.getCurrentICR(irPosman, WBTC, BOB, wbtcPriceFeed.getPrice()),
            bobICRBeforeRedistribution
        );
    }
}
