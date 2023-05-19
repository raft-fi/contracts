// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IPositionManager } from "../contracts/Interfaces/IPositionManager.sol";
import { IRToken } from "../contracts/Interfaces/IRToken.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { FlashMintLiquidator } from "../contracts/FlashMintLiquidator.sol";
import { PositionManager } from "../contracts/PositionManager.sol";
import { SplitLiquidationCollateral } from "../contracts/SplitLiquidationCollateral.sol";
import { PriceFeedTestnet } from "./mocks/PriceFeedTestnet.sol";
import { MockAMM } from "./mocks/MockAMM.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";
import { IERC20Indexable } from "../contracts/Interfaces/IERC20Indexable.sol";

contract PositionManagerLiquidationTest is TestSetup {
    PriceFeedTestnet public priceFeed;
    IRToken public rToken;
    FlashMintLiquidator public liquidator;
    MockAMM public mockAmm;

    function setUp() public override {
        super.setUp();

        priceFeed = new PriceFeedTestnet();
        positionManager.addCollateralToken(collateralToken, priceFeed, splitLiquidationCollateral);

        rToken = positionManager.rToken();

        mockAmm = new MockAMM(collateralToken, rToken, 200e18);
        liquidator = new FlashMintLiquidator(positionManager, mockAmm, collateralToken);

        collateralToken.mint(ALICE, 10e36);
        collateralToken.mint(BOB, 10e36);
        collateralToken.mint(address(mockAmm), 10e36);

        vm.startPrank(address(positionManager));
        positionManager.rToken().mint(address(mockAmm), 10e36);
        vm.stopPrank();

        setPriceHelper(200e18);
    }

    function setPriceHelper(uint256 price) public {
        priceFeed.setPrice(price);
        mockAmm.setRate(price);
    }

    // Closes a position that has 100% < ICR < 110% (MCR)
    function testSuccessfulPositionLiquidation() public {
        assertEq(rToken.balanceOf(address(this)), 0);
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 20e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: BOB,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 price = priceFeed.getPrice();

        uint256 icrBefore = PositionManagerUtils.getCurrentICR(positionManager, collateralToken, BOB, price);
        assertEq(icrBefore, 2e18);

        // Bob increases debt to 180 R, lowering his ICR to 1.11
        uint256 targetICR = 1_111_111_111_111_111_111;
        vm.startPrank(BOB);
        PositionManagerUtils.withdrawDebt({
            positionManager: positionManager,
            collateralToken: collateralToken,
            priceFeed: priceFeed,
            position: BOB,
            icr: targetICR
        });
        vm.stopPrank();

        uint256 icrAfter = PositionManagerUtils.getCurrentICR(positionManager, collateralToken, BOB, price);
        assertEq(icrAfter, targetICR);

        // price drops to 1ETH:198R, reducing Bob's ICR between 100% and 110%
        setPriceHelper(198e18);

        // liquidate position
        liquidator.liquidate(BOB, "");

        // Bob's position is closed
        (, IERC20Indexable raftDebtToken,) = positionManager.raftCollateralTokens(collateralToken);
        assertEq(raftDebtToken.balanceOf(BOB), 0);
        assertGt(rToken.balanceOf(address(this)), 535e18);
    }
}
