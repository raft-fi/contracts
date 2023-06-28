// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IPositionManager } from "../contracts/Interfaces/IPositionManager.sol";
import { IRToken } from "../contracts/Interfaces/IRToken.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { FlashMintLiquidatorWrappedCollateral } from "../contracts/FlashMintLiquidatorWrappedCollateral.sol";
import { PositionManager } from "../contracts/PositionManager.sol";
import { SplitLiquidationCollateral } from "../contracts/SplitLiquidationCollateral.sol";
import { PriceFeedTestnet } from "./mocks/PriceFeedTestnet.sol";
import { MockAMM } from "./mocks/MockAMM.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";
import { IERC20Indexable } from "../contracts/Interfaces/IERC20Indexable.sol";
import { IERC20Wrapped } from "../contracts/Interfaces/IERC20Wrapped.sol";
import { WrappedCollateralToken } from "../contracts/WrappedCollateralToken.sol";

// solhint-disable max-line-length
contract FlashMintLiquidatorWrappedCollateralTest is TestSetup {
    PriceFeedTestnet public priceFeed;
    IRToken public rToken;
    FlashMintLiquidatorWrappedCollateral public liquidator;
    MockAMM public mockAmm;
    WrappedCollateralToken public wrappedCollateralToken;

    function setUp() public override {
        super.setUp();

        priceFeed = new PriceFeedTestnet();
        wrappedCollateralToken = new WrappedCollateralToken(
            collateralToken, "Wrapped Collateral Token", "WCT", type(uint256).max, type(uint256).max, address(positionManager)
        );
        positionManager.addCollateralToken(wrappedCollateralToken, priceFeed, splitLiquidationCollateral);

        rToken = positionManager.rToken();

        mockAmm = new MockAMM(collateralToken, rToken, 200e18);
        liquidator =
        new FlashMintLiquidatorWrappedCollateral(positionManager, mockAmm, IERC20Wrapped(address(wrappedCollateralToken)));

        collateralToken.mint(ALICE, 20e36);

        wrappedCollateralToken.whitelistAddress(ALICE, true);
        vm.startPrank(ALICE);
        collateralToken.approve(address(wrappedCollateralToken), 20e36);
        wrappedCollateralToken.depositForWithAccountCheck(ALICE, ALICE, 10e36);
        wrappedCollateralToken.depositForWithAccountCheck(BOB, BOB, 10e36);
        vm.stopPrank();

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
    function testSuccessfulPositionLiquidationWrappedToken() public {
        assertEq(rToken.balanceOf(address(this)), 0);
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: wrappedCollateralToken,
            position: ALICE,
            icr: 20e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: wrappedCollateralToken,
            position: BOB,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 price = priceFeed.getPrice();

        uint256 icrBefore = PositionManagerUtils.getCurrentICR(positionManager, wrappedCollateralToken, BOB, price);
        assertEq(icrBefore, 2e18);

        // Bob increases debt to 180 R, lowering his ICR to 1.11
        uint256 targetICR = 1_111_111_111_111_111_111;
        vm.startPrank(BOB);
        PositionManagerUtils.withdrawDebt({
            positionManager: positionManager,
            collateralToken: wrappedCollateralToken,
            priceFeed: priceFeed,
            position: BOB,
            icr: targetICR
        });
        vm.stopPrank();

        uint256 icrAfter = PositionManagerUtils.getCurrentICR(positionManager, wrappedCollateralToken, BOB, price);
        assertEq(icrAfter, targetICR);

        // price drops to 1ETH:198R, reducing Bob's ICR between 100% and 110%
        setPriceHelper(198e18);

        // liquidate position
        liquidator.liquidate(BOB, "");

        // Bob's position is closed
        (, IERC20Indexable raftDebtToken,,,,,,,,) = positionManager.collateralInfo(wrappedCollateralToken);
        assertEq(raftDebtToken.balanceOf(BOB), 0);
        assertGt(rToken.balanceOf(address(this)), 535e18);
    }
}
