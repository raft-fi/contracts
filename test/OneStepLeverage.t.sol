// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { OneStepLeverage } from "../contracts/OneStepLeverage.sol";
import { PositionManager } from "../contracts/PositionManager.sol";
import { IAMM } from "../contracts/Interfaces/IAMM.sol";
import { IOneStepLeverage } from "../contracts/Interfaces/IOneStepLeverage.sol";
import { IPositionManager } from "../contracts/Interfaces/IPositionManager.sol";
import { IPositionManagerDependent } from "../contracts/Interfaces/IPositionManagerDependent.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";
import { MockAMM } from "./mocks/MockAMM.sol";
import { SplitLiquidationCollateral } from "../contracts/SplitLiquidationCollateral.sol";
import { PriceFeedTestnet } from "./mocks/PriceFeedTestnet.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { IERC20Indexable } from "../contracts/Interfaces/IERC20Indexable.sol";

contract OneStepLeverageTest is TestSetup {
    using Fixed256x18 for uint256;

    uint256 public constant LIQUIDATION_PROTOCOL_FEE = 0;

    PriceFeedTestnet public priceFeed;
    IPositionManager public positionManager;
    OneStepLeverage public oneStepLeverage;

    function setUp() public override {
        super.setUp();

        priceFeed = new PriceFeedTestnet();

        positionManager = new PositionManager(
            new SplitLiquidationCollateral()
        );
        positionManager.addCollateralToken(collateralToken, priceFeed);

        IAMM mockAmm = new MockAMM(collateralToken, positionManager.rToken(), 200e18);
        oneStepLeverage = new OneStepLeverage(positionManager, mockAmm, collateralToken);

        collateralToken.mint(address(oneStepLeverage.amm()), 10e36);
        collateralToken.mint(ALICE, 10e36);
        vm.startPrank(address(positionManager));
        positionManager.rToken().mint(address(this), 1_000_000_000e18);
        positionManager.rToken().mint(address(oneStepLeverage.amm()), 10e36);
        vm.stopPrank();

        vm.prank(ALICE);
        positionManager.whitelistDelegate(address(oneStepLeverage), true);

        collateralToken.mint(BOB, 10e36);
        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: BOB,
            icr: 2e18
        });
        vm.stopPrank();
    }

    function testCannotCreateOneStepLeverage() public {
        IAMM mockAmm = new MockAMM(collateralToken, positionManager.rToken(), 200e18);

        vm.expectRevert(IPositionManagerDependent.PositionManagerCannotBeZero.selector);
        new OneStepLeverage(IPositionManager(address(0)), mockAmm, collateralToken);

        vm.expectRevert(IOneStepLeverage.AmmCannotBeZero.selector);
        new OneStepLeverage(positionManager, IAMM(address(0)), collateralToken);

        vm.expectRevert(IOneStepLeverage.CollateralTokenCannotBeZero.selector);
        new OneStepLeverage(positionManager, mockAmm, IERC20Indexable(address(0)));
    }

    function testCannotProvideZeroDebtChange() public {
        uint256 collateralAmount = 420e18;

        vm.startPrank(ALICE);
        collateralToken.approve(address(oneStepLeverage), collateralAmount);

        vm.expectRevert(IOneStepLeverage.ZeroDebtChange.selector);
        oneStepLeverage.manageLeveragedPosition(0, true, collateralAmount, true, "", 1, MathUtils._100_PERCENT);
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
            targetDebt, true, collateralAmount, true, "", minReturn, MathUtils._100_PERCENT
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
            targetDebt, true, collateralAmount, true, "", minReturn, MathUtils._100_PERCENT
        );

        uint256 collateralToSwap = targetDebt * (1e18 + 1e15) / price;
        (IERC20Indexable raftCollateralToken,) = positionManager.raftCollateralTokens(collateralToken);
        uint256 principalDecrease = raftCollateralToken.balanceOf(ALICE) - collateralToSwap;

        oneStepLeverage.manageLeveragedPosition(
            positionManager.raftDebtToken().balanceOf(ALICE),
            false,
            principalDecrease,
            false,
            "",
            collateralToSwap,
            MathUtils._100_PERCENT
        );

        assertEq(positionManager.raftDebtToken().balanceOf(ALICE), 0);
        assertEq(raftCollateralToken.balanceOf(ALICE), 0);
    }

    function checkEffectiveLeverage(address position, uint256 targetLeverageMultiplier) internal {
        (IERC20Indexable raftCollateralToken,) = positionManager.raftCollateralTokens(collateralToken);
        uint256 debtAfter = positionManager.raftDebtToken().balanceOf(position);
        uint256 collAfter = raftCollateralToken.balanceOf(position);
        uint256 collAfterExpressedInR = positionManager.priceFeeds(collateralToken).fetchPrice().mulDown(collAfter);
        uint256 effectiveLeverage = collAfterExpressedInR.divDown(collAfterExpressedInR - debtAfter);
        assertEq(effectiveLeverage, targetLeverageMultiplier);
    }
}
