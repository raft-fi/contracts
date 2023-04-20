// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {Fixed256x18} from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import "../contracts/OneStepLeverage.sol";
import "../contracts/PositionManager.sol";
import "../contracts/Interfaces/IAMM.sol";
import "./utils/PositionManagerUtils.sol";
import "./utils/TestSetup.t.sol";
import {MockAMM} from "./TestContracts/MockAMM.sol";
import {SplitLiquidationCollateral} from "../contracts/SplitLiquidationCollateral.sol";

contract OneStepLeverageTest is TestSetup {
    using Fixed256x18 for uint256;

    uint256 public constant POSITIONS_SIZE = 10;
    uint256 public constant LIQUIDATION_PROTOCOL_FEE = 0;

    PriceFeedTestnet public priceFeed;
    IPositionManager public positionManager;
    OneStepLeverage public oneStepLeverage;

    function setUp() public override {
        super.setUp();

        priceFeed = new PriceFeedTestnet();

        positionManager = new PositionManager(
            new address[](0),
            new SplitLiquidationCollateral()
        );
        positionManager.addCollateralToken(collateralToken, priceFeed, POSITIONS_SIZE);

        IAMM mockAmm = new MockAMM(collateralToken, positionManager.rToken(), 200e18);
        oneStepLeverage = new OneStepLeverage(positionManager, mockAmm, collateralToken);
        positionManager.setGlobalDelegateWhitelist(address(oneStepLeverage), true);

        collateralToken.mint(address(oneStepLeverage.amm()), 10e36);
        collateralToken.mint(ALICE, 10e36);
        vm.startPrank(address(positionManager));
        positionManager.rToken().mint(address(this), 1_000_000_000e18);
        positionManager.rToken().mint(address(oneStepLeverage.amm()), 10e36);
        vm.stopPrank();

        collateralToken.mint(BOB, 10e36);
        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();
    }

    function testOpenLeveragedPosition() public {
        uint256 collateralAmount = 420e18;
        uint256 leverageMultiplier = 9e18;
        uint256 price = priceFeed.getPrice();
        uint256 targetDebt = collateralAmount.mulDown(price).mulDown(leverageMultiplier - 1e18);
        uint256 minReturn = collateralAmount.mulDown(leverageMultiplier - 1e18).mulDown(1e18 - 1e15);

        vm.startPrank(ALICE);
        collateralToken.approve(address(oneStepLeverage), collateralAmount);
        oneStepLeverage.manageLeveragedPosition(
            targetDebt, true, collateralAmount, true, "", minReturn, ALICE, ALICE, MathUtils._100_PERCENT
        );

        checkEffectiveLeverage(ALICE, leverageMultiplier);
    }

    function testAdjustLeveragedPositionToClosePosition() public {
        uint256 collateralAmount = 420e18;
        uint256 leverageMultiplier = 9e18;
        uint256 price = priceFeed.getPrice();
        uint256 targetDebt = collateralAmount.mulDown(price).mulDown(leverageMultiplier - 1e18);
        uint256 minReturn = collateralAmount.mulDown(leverageMultiplier - 1e18).mulDown(1e18 - 1e15);

        vm.startPrank(ALICE);
        collateralToken.approve(address(oneStepLeverage), collateralAmount);
        oneStepLeverage.manageLeveragedPosition(
            targetDebt, true, collateralAmount, true, "", minReturn, ALICE, ALICE, MathUtils._100_PERCENT
        );

        uint256 collateralToSwap = targetDebt * (1e18 + 1e15) / 200e18;
        uint256 principalDecrease =
            positionManager.raftCollateralTokens(collateralToken).balanceOf(ALICE) - collateralToSwap;

        oneStepLeverage.manageLeveragedPosition(
            positionManager.raftDebtToken().balanceOf(ALICE),
            false,
            principalDecrease,
            false,
            "",
            collateralToSwap,
            ALICE,
            ALICE,
            MathUtils._100_PERCENT
        );

        assertEq(positionManager.raftDebtToken().balanceOf(ALICE), 0);
        assertEq(positionManager.raftCollateralTokens(collateralToken).balanceOf(ALICE), 0);
    }

    function checkEffectiveLeverage(address borrower, uint256 targetLeverageMultiplier) internal {
        uint256 debtAfter = positionManager.raftDebtToken().balanceOf(borrower);
        uint256 collAfter = positionManager.raftCollateralTokens(collateralToken).balanceOf(borrower);
        uint256 collAfterExpressedInR = positionManager.priceFeeds(collateralToken).fetchPrice() * collAfter / 1e18;
        uint256 effectiveLeverage = collAfterExpressedInR * 1e18 / (collAfterExpressedInR - debtAfter);
        assertEq(effectiveLeverage, targetLeverageMultiplier);
    }
}
