// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IPositionManager} from "../contracts/Interfaces/IPositionManager.sol";
import {PositionManager} from "../contracts/PositionManager.sol";
import {IRToken} from "../contracts/Interfaces/IRToken.sol";
import {MathUtils} from "../contracts/Dependencies/MathUtils.sol";
import {PriceFeedTestnet} from "./TestContracts/PriceFeedTestnet.sol";
import {PositionManagerUtils} from "./utils/PositionManagerUtils.sol";
import {TestSetup} from "./utils/TestSetup.t.sol";

contract PositionManagerClosePositionTest is TestSetup {
    uint256 public constant POSITIONS_SIZE = 10;
    uint256 public constant LIQUIDATION_PROTOCOL_FEE = 0;
    uint256 public constant DEFAULT_PRICE = 200e18;

    PriceFeedTestnet public priceFeed;
    IPositionManager public positionManager;
    IRToken public rToken;

    function setUp() public override {
        super.setUp();

        priceFeed = new PriceFeedTestnet();
        positionManager = new PositionManager(
            LIQUIDATION_PROTOCOL_FEE,
            new address[](0),
            SPLIT_LIQUIDATION_COLLATERAL
        );
        positionManager.addCollateralToken(collateralToken, priceFeed, POSITIONS_SIZE);

        rToken = positionManager.rToken();

        collateralToken.mint(ALICE, 10e36);
        collateralToken.mint(BOB, 10e36);
        collateralToken.mint(CAROL, 10e36);
    }

    // Reverts when position is the only one in the system
    function testInvalidClosureLastPosition() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 100000e18,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 alicePositionCollateral = positionManager.raftCollateralTokens(collateralToken).balanceOf(ALICE);

        // Artificially mint to Alice so she has enough to close her position
        vm.prank(address(positionManager));
        rToken.mint(ALICE, 100000e18);

        // Check she has more R than her position debt
        uint256 aliceBalance = rToken.balanceOf(ALICE);
        uint256 aliceDebt = positionManager.raftDebtToken().balanceOf(ALICE);
        assertGt(aliceBalance, aliceDebt);

        // Alice attempts to close her position
        vm.startPrank(ALICE);
        vm.expectRevert(IPositionManager.OnlyOnePositionInSystem.selector);
        positionManager.managePosition(
            collateralToken, alicePositionCollateral, false, aliceDebt, false, ALICE, ALICE, 0
        );
    }

    // Reduces position's collateral and debt to zero
    function testCollateralDebtToZero() public {
        uint256 aliceCollateralBefore = collateralToken.balanceOf(ALICE);

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 10000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 10000e18,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 alicePositionCollateralBefore = positionManager.raftCollateralTokens(collateralToken).balanceOf(ALICE);
        uint256 aliceDebtBefore = positionManager.raftDebtToken().balanceOf(ALICE);
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
        positionManager.managePosition(
            collateralToken, alicePositionCollateralBefore, false, aliceDebtBefore, false, ALICE, ALICE, 0
        );

        uint256 aliceCollateralAfter = collateralToken.balanceOf(ALICE);
        uint256 alicePositionCollateralAfter = positionManager.raftCollateralTokens(collateralToken).balanceOf(ALICE);
        uint256 aliceDebtAfter = positionManager.raftDebtToken().balanceOf(ALICE);
        uint256 aliceDebtBalanceAfter = rToken.balanceOf(ALICE);
        uint256 bobPositionCollateralAfter = positionManager.raftCollateralTokens(collateralToken).balanceOf(BOB);
        uint256 positionManagerCollateralBalance = collateralToken.balanceOf(address(positionManager));

        assertEq(alicePositionCollateralAfter, 0);
        assertEq(aliceDebtAfter, 0);
        assertEq(positionManagerCollateralBalance, bobPositionCollateralAfter);
        assertEq(aliceCollateralAfter, aliceCollateralBefore);
        assertEq(aliceDebtBalanceAfter, aliceRBalanceBefore - aliceDebtBefore);
    }

    // Succeeds when borrower's R balance is equals to his entire debt and borrowing rate = 0
    function testSuccessfulClosureBorrowingRateZero() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 15000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 5000e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Check if borrowing rate is 0
        uint256 borrowingRate = positionManager.getBorrowingRate();
        assertEq(borrowingRate, 0);

        // Confirm Bob's R balance is less than his position debt
        uint256 bobRBalance = rToken.balanceOf(BOB);
        uint256 bobPositionCollateral = positionManager.raftCollateralTokens(collateralToken).balanceOf(BOB);
        uint256 bobPositionDebt = positionManager.raftDebtToken().balanceOf(BOB);

        assertEq(bobPositionDebt, bobRBalance);

        vm.prank(BOB);
        positionManager.managePosition(
            collateralToken, bobPositionCollateral, false, bobPositionDebt, false, BOB, BOB, 0
        );
    }

    // Reverts if borrower has insufficient R balance to repay his entire debt when borrowing rate > 0%
    function testUnsuccessfulClosureBorrowingRateNonZero() public {
        positionManager.setBorrowingSpread(5 * MathUtils._100_PERCENT / 1000);

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 15000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 5000e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Check if borrowing rate > 0
        uint256 borrowingRate = positionManager.getBorrowingRate();
        assertGt(borrowingRate, 0);

        // Confirm Bob's R balance is less than his position debt
        uint256 bobRBalance = rToken.balanceOf(BOB);
        uint256 bobPositionCollateral = positionManager.raftCollateralTokens(collateralToken).balanceOf(BOB);
        uint256 bobPositionDebt = positionManager.raftDebtToken().balanceOf(BOB);

        assertGt(bobPositionDebt, bobRBalance);

        vm.prank(BOB);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        positionManager.managePosition(
            collateralToken, bobPositionCollateral, false, bobPositionDebt, false, BOB, BOB, 0
        );
    }
}
