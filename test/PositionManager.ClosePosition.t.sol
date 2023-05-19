// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IPositionManager } from "../contracts/Interfaces/IPositionManager.sol";
import { PositionManager } from "../contracts/PositionManager.sol";
import { IERC20Indexable } from "../contracts/Interfaces/IERC20Indexable.sol";
import { IRToken } from "../contracts/Interfaces/IRToken.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { PriceFeedTestnet } from "./mocks/PriceFeedTestnet.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";

contract PositionManagerClosePositionTest is TestSetup {
    uint256 public constant DEFAULT_PRICE = 200e18;

    PriceFeedTestnet public priceFeed;
    IRToken public rToken;

    function setUp() public override {
        super.setUp();

        priceFeed = new PriceFeedTestnet();
        positionManager.addCollateralToken(collateralToken, priceFeed, splitLiquidationCollateral);

        rToken = positionManager.rToken();

        collateralToken.mint(ALICE, 10e36);
        collateralToken.mint(BOB, 10e36);
        collateralToken.mint(CAROL, 10e36);
    }

    // Reduces position's collateral and debt to zero
    function testCollateralDebtToZero() public {
        uint256 aliceCollateralBefore = collateralToken.balanceOf(ALICE);

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            extraDebtAmount: 10_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: BOB,
            extraDebtAmount: 10_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        (IERC20Indexable raftCollateralToken, IERC20Indexable raftDebtToken,) =
            positionManager.raftCollateralTokens(collateralToken);
        uint256 alicePositionCollateralBefore = raftCollateralToken.balanceOf(ALICE);
        uint256 aliceDebtBefore = raftDebtToken.balanceOf(ALICE);
        uint256 bobRBalance = rToken.balanceOf(BOB);

        assertGt(alicePositionCollateralBefore, 0);
        assertGt(aliceDebtBefore, 0);
        assertGt(bobRBalance, 0);

        // To compensate borrowing fees
        vm.prank(BOB);
        rToken.transfer(ALICE, bobRBalance / 2);

        uint256 aliceRBalanceBefore = rToken.balanceOf(ALICE);
        assertGt(aliceRBalanceBefore, 0);

        // Alice attempts to close position
        vm.prank(ALICE);
        positionManager.managePosition(collateralToken, ALICE, 0, false, aliceDebtBefore, false, 0, emptySignature);

        uint256 aliceCollateralAfter = collateralToken.balanceOf(ALICE);
        uint256 alicePositionCollateralAfter = raftCollateralToken.balanceOf(ALICE);
        uint256 aliceDebtAfter = raftDebtToken.balanceOf(ALICE);
        uint256 aliceDebtBalanceAfter = rToken.balanceOf(ALICE);
        uint256 bobPositionCollateralAfter = raftCollateralToken.balanceOf(BOB);
        uint256 positionManagerCollateralBalance = collateralToken.balanceOf(address(positionManager));

        assertEq(alicePositionCollateralAfter, 0);
        assertEq(aliceDebtAfter, 0);
        assertEq(positionManagerCollateralBalance, bobPositionCollateralAfter);
        assertEq(aliceCollateralAfter, aliceCollateralBefore);
        assertEq(aliceDebtBalanceAfter, aliceRBalanceBefore - aliceDebtBefore);
    }

    // Reduces position's collateral and debt to zero
    function testCollateralWithdrawsWhenDebtZero() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            extraDebtAmount: 10_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: BOB,
            extraDebtAmount: 10_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        (IERC20Indexable raftCollateralToken, IERC20Indexable raftDebtToken,) =
            positionManager.raftCollateralTokens(collateralToken);
        uint256 alicePositionCollateralBefore = raftCollateralToken.balanceOf(ALICE);
        uint256 aliceDebtBefore = raftDebtToken.balanceOf(ALICE);
        uint256 bobRBalance = rToken.balanceOf(BOB);

        assertGt(alicePositionCollateralBefore, 0);
        assertGt(aliceDebtBefore, 0);
        assertGt(bobRBalance, 0);

        // To compensate borrowing fees
        vm.prank(BOB);
        rToken.transfer(ALICE, bobRBalance / 2);

        uint256 aliceRBalanceBefore = rToken.balanceOf(ALICE);
        assertGt(aliceRBalanceBefore, 0);

        // Alice attempts to close position but leave some collateral
        vm.prank(ALICE);
        positionManager.managePosition(collateralToken, ALICE, 0, false, aliceDebtBefore, false, 0, emptySignature);
        assertEq(raftCollateralToken.balanceOf(ALICE), 0);
    }

    // Succeeds when borrower's R balance is equals to his entire debt and borrowing rate = 0
    function testSuccessfulClosureBorrowingRateZero() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            extraDebtAmount: 15_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: BOB,
            extraDebtAmount: 5000e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Check if borrowing rate is 0
        uint256 borrowingRate = positionManager.getBorrowingRate(collateralToken);
        assertEq(borrowingRate, 0);

        (, IERC20Indexable raftDebtToken,) = positionManager.raftCollateralTokens(collateralToken);
        // Confirm Bob's R balance is less than his position debt
        uint256 bobRBalance = rToken.balanceOf(BOB);
        uint256 bobPositionDebt = raftDebtToken.balanceOf(BOB);

        assertEq(bobPositionDebt, bobRBalance);

        vm.prank(BOB);
        positionManager.managePosition(collateralToken, BOB, 0, false, bobPositionDebt, false, 0, emptySignature);
    }

    // Reverts if borrower has insufficient R balance to repay his entire debt when borrowing rate > 0%
    function testUnsuccessfulClosureBorrowingRateNonZero() public {
        positionManager.setBorrowingSpread(collateralToken, 5 * MathUtils._100_PERCENT / 1000);

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            extraDebtAmount: 15_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: BOB,
            extraDebtAmount: 5000e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Check if borrowing rate > 0
        uint256 borrowingRate = positionManager.getBorrowingRate(collateralToken);
        assertGt(borrowingRate, 0);

        (, IERC20Indexable raftDebtToken,) = positionManager.raftCollateralTokens(collateralToken);

        // Confirm Bob's R balance is less than his position debt
        uint256 bobRBalance = rToken.balanceOf(BOB);
        uint256 bobPositionDebt = raftDebtToken.balanceOf(BOB);

        assertGt(bobPositionDebt, bobRBalance);

        vm.prank(BOB);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        positionManager.managePosition(collateralToken, BOB, 0, false, bobPositionDebt, false, 0, emptySignature);
    }
}
