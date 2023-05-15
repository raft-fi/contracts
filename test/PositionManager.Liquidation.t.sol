// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IPositionManager } from "../contracts/Interfaces/IPositionManager.sol";
import { IRToken } from "../contracts/Interfaces/IRToken.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { PositionManager } from "../contracts/PositionManager.sol";
import { SplitLiquidationCollateral } from "../contracts/SplitLiquidationCollateral.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";

contract PositionManagerLiquidationTest is TestSetup {
    IRToken public rToken;

    function setUp() public override {
        super.setUp();

        rToken = positionManager.rToken();

        collateralToken.mint(ALICE, 10e36);
        collateralToken.mint(BOB, 10e36);
        collateralToken.mint(CAROL, 10e36);
        collateralToken.mint(DAVE, 10e36);
        collateralToken.mint(EVE, 10e36);
    }

    // Closes a position that has 100% < ICR < 110% (MCR)
    function testSuccessfulPositionLiquidation() public {
        vm.prank(address(positionManager));
        rToken.mint(address(this), 1_000_000e18);

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
        priceFeed.setPrice(198e18);

        // liquidate position
        positionManager.liquidate(BOB);

        // Bob's position is closed
        assertEq(positionManager.raftDebtToken().balanceOf(BOB), 0);
    }

    function testLiquidateLastDebt() public {
        vm.prank(address(positionManager));
        rToken.mint(address(this), 1_000_000e18);

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 2e18
        });
        vm.stopPrank();

        priceFeed.setPrice(105e18);
        uint256 price = priceFeed.getPrice();

        uint256 aliceICR = PositionManagerUtils.getCurrentICR(positionManager, collateralToken, ALICE, price);
        assertEq(aliceICR, 105 * MathUtils._100_PERCENT / 100);

        // liquidate position
        vm.expectRevert(IPositionManager.CannotLiquidateLastPosition.selector);
        positionManager.liquidate(ALICE);
    }

    // Liquidates undercollateralized position if there are two positions in the system
    function testSuccessfulLiquidationTwoPositionsSystem() public {
        vm.prank(address(positionManager));
        rToken.mint(address(this), 1_000_000e18);

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: BOB,
            extraDebtAmount: 0,
            icr: 200e18,
            amount: 100 ether
        });
        vm.stopPrank();

        // Alice creates a single position with 0.7 ETH and a debt of 70 R
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 2e18
        });
        vm.stopPrank();

        // Set ETH:USD price to 105
        priceFeed.setPrice(105e18);
        uint256 price = priceFeed.getPrice();

        uint256 aliceICR = PositionManagerUtils.getCurrentICR(positionManager, collateralToken, ALICE, price);
        assertEq(aliceICR, 105 * MathUtils._100_PERCENT / 100);

        // Liquidate the position
        positionManager.liquidate(ALICE);

        assertEq(positionManager.raftDebtToken().balanceOf(ALICE), 0);
        assertGt(positionManager.raftDebtToken().balanceOf(BOB), 0);
    }

    // Reverts if position is non-existent or has been closed
    function testLiquidateNonExistentPosition() public {
        vm.prank(address(positionManager));
        rToken.mint(address(this), 1_000_000e18);

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 4e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: BOB,
            icr: 2.1e18
        });
        vm.stopPrank();

        assertEq(positionManager.raftDebtToken().balanceOf(CAROL), 0);

        vm.expectRevert(IPositionManager.NothingToLiquidate.selector);
        positionManager.liquidate(CAROL);

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: CAROL,
            icr: 2e18
        });
        vm.stopPrank();

        assertGt(positionManager.raftDebtToken().balanceOf(CAROL), 0);

        // Price drops, Carol ICR falls below MCR
        priceFeed.setPrice(105e18);

        // Carol liquidated, and her position is closed
        positionManager.liquidate(CAROL);

        assertEq(positionManager.raftDebtToken().balanceOf(CAROL), 0);

        vm.expectRevert(IPositionManager.NothingToLiquidate.selector);
        positionManager.liquidate(CAROL);
    }

    // Does nothing if position has > 110% ICR
    function testInvalidLiquidationICRGreaterThan110Percent() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 3e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: BOB,
            icr: 3e18
        });
        vm.stopPrank();

        uint256 price = priceFeed.getPrice();

        // Check Bob's ICR > 110%
        uint256 bobICR = PositionManagerUtils.getCurrentICR(positionManager, collateralToken, BOB, price);
        assertTrue(bobICR > MathUtils.MCR);

        // Attempt to liquidate Bob
        vm.expectRevert(IPositionManager.NothingToLiquidate.selector);
        positionManager.liquidate(BOB);

        // Check Bob active, check Alice active
        assertGt(positionManager.raftDebtToken().balanceOf(BOB), 0);
        assertGt(positionManager.raftDebtToken().balanceOf(ALICE), 0);
    }

    function testInvalidLiquidationICREqualTo110Percent() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 22e17
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: BOB,
            icr: 22e17
        });
        vm.stopPrank();

        // Set ETH:USD price to 100
        priceFeed.setPrice(100e18);
        uint256 price = priceFeed.getPrice();

        // Check Bob's ICR == 110%
        uint256 bobICR = PositionManagerUtils.getCurrentICR(positionManager, collateralToken, BOB, price);
        assertTrue(bobICR == MathUtils.MCR);

        // Attempt to liquidate Bob
        vm.expectRevert(IPositionManager.NothingToLiquidate.selector);
        positionManager.liquidate(BOB);

        // Check Bob active, check Alice active
        assertGt(positionManager.raftDebtToken().balanceOf(BOB), 0);
        assertGt(positionManager.raftDebtToken().balanceOf(ALICE), 0);
    }
}
