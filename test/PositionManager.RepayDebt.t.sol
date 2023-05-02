// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IPositionManager } from "../contracts/Interfaces/IPositionManager.sol";
import { IRToken } from "../contracts/Interfaces/IRToken.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { PositionManager } from "../contracts/PositionManager.sol";
import { PriceFeedTestnet } from "./mocks/PriceFeedTestnet.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";

contract PositionManagerRepayDebtTest is TestSetup {
    uint256 public constant DEFAULT_PRICE = 200e18;

    PriceFeedTestnet public priceFeed;
    IPositionManager public positionManager;
    IRToken public rToken;

    function setUp() public override {
        super.setUp();

        priceFeed = new PriceFeedTestnet();
        positionManager = new PositionManager(
            splitLiquidationCollateral
        );
        positionManager.addCollateralToken(collateralToken, priceFeed);

        rToken = positionManager.rToken();

        collateralToken.mint(ALICE, 10e36);
        collateralToken.mint(BOB, 10e36);
        collateralToken.mint(CAROL, 10e36);
    }

    // reverts when repayment would leave position with ICR < MCR
    function testInvalidICR() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: BOB,
            icr: 10e18
        });
        vm.stopPrank();

        // Price drops
        priceFeed.setPrice(100e18);
        uint256 price = priceFeed.getPrice();

        assertLt(PositionManagerUtils.getCurrentICR(positionManager, collateralToken, ALICE, price), MathUtils.MCR);

        uint256 repaymentAmount = 1e18;

        vm.startPrank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPositionManager.NetDebtBelowMinimum.selector,
                positionManager.splitLiquidationCollateral().LOW_TOTAL_DEBT() - repaymentAmount
            )
        );
        positionManager.managePosition(collateralToken, ALICE, 0, false, repaymentAmount, false, 0, emptySignature);
        vm.stopPrank();
    }

    // Succeeds when it would leave position with net debt >= minimum net debt
    function testSuccessfulRepayAboveNetDebtMin() public {
        // Make the R request 2 wei above min net debt to correct for floor division, and make
        // net debt = min net debt + 1 wei
        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), 100e30);
        positionManager.managePosition(
            collateralToken,
            ALICE,
            100e30,
            true,
            PositionManagerUtils.getNetBorrowingAmount(
                positionManager, positionManager.splitLiquidationCollateral().LOW_TOTAL_DEBT() + 2
            ),
            true,
            MathUtils._100_PERCENT,
            emptySignature
        );
        vm.stopPrank();

        vm.prank(ALICE);
        positionManager.managePosition(collateralToken, ALICE, 0, false, 1, false, 0, emptySignature);

        vm.startPrank(BOB);
        collateralToken.approve(address(positionManager), 100e30);
        positionManager.managePosition(
            collateralToken, BOB, 100e30, true, 20e25, true, MathUtils._100_PERCENT, emptySignature
        );
        vm.stopPrank();

        vm.prank(BOB);
        positionManager.managePosition(collateralToken, BOB, 0, false, 19e25, false, 0, emptySignature);
    }

    // Reverts when borrowing rate = 0% and it would leave position with net debt < minimum net debt
    function testRevertNetDebtBelowMinWhenBorrowingRateZero() public {
        assertEq(positionManager.getBorrowingRate(), 0);

        // Make the R request 1 wei above min net debt to correct for floor division, and make
        // net debt = min net debt + 1 wei
        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), 100e30);
        positionManager.managePosition(
            collateralToken,
            ALICE,
            100e30,
            true,
            PositionManagerUtils.getNetBorrowingAmount(
                positionManager, positionManager.splitLiquidationCollateral().LOW_TOTAL_DEBT() + 1
            ),
            true,
            MathUtils._100_PERCENT,
            emptySignature
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IPositionManager.NetDebtBelowMinimum.selector,
                positionManager.splitLiquidationCollateral().LOW_TOTAL_DEBT() - 1
            )
        );
        positionManager.managePosition(collateralToken, ALICE, 0, false, 2, false, 0, emptySignature);
        vm.stopPrank();
    }

    // Reverts when borrowing rate > 0% and it would leave position with net debt < minimum net debt
    function testRevertNetDebtBelowMinWhenBorrowingRateNonZero() public {
        positionManager.setBorrowingSpread(positionManager.MAX_BORROWING_SPREAD() / 2);
        assertGt(positionManager.getBorrowingRate(), 0);

        // Make the R request 1 wei above min net debt to correct for floor division, and make
        // net debt = min net debt + 1 wei
        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), 100e30);
        positionManager.managePosition(
            collateralToken,
            ALICE,
            100e30,
            true,
            PositionManagerUtils.getNetBorrowingAmount(
                positionManager, positionManager.splitLiquidationCollateral().LOW_TOTAL_DEBT() + 1
            ),
            true,
            MathUtils._100_PERCENT,
            emptySignature
        );
        vm.stopPrank();

        vm.startPrank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPositionManager.NetDebtBelowMinimum.selector,
                positionManager.splitLiquidationCollateral().LOW_TOTAL_DEBT() - 1
            )
        );
        positionManager.managePosition(collateralToken, ALICE, 0, false, 2, false, 0, emptySignature);
        vm.stopPrank();
    }

    // Reverts when calling address does not have active position
    function testNoActivePosition() public {
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

        vm.prank(BOB);
        positionManager.managePosition(collateralToken, BOB, 0, false, 10e18, false, 0, emptySignature);

        // Carol with no active position attempts to repay R
        vm.prank(CAROL);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        positionManager.managePosition(collateralToken, CAROL, 0, false, 10e18, false, 0, emptySignature);
    }

    // Reverts when attempted repayment is > the debt of the position
    function testUnsuccessfulRepayLargerThanDebt() public {
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

        uint256 aliceDebt = positionManager.raftDebtToken().balanceOf(ALICE);

        // Bob successfully repays some R
        vm.prank(BOB);
        positionManager.managePosition(collateralToken, BOB, 0, false, 10e18, false, 0, emptySignature);

        // Alice attempts to repay more than her debt
        vm.prank(ALICE);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        positionManager.managePosition(collateralToken, ALICE, 0, false, aliceDebt + 1e18, false, 0, emptySignature);
    }

    // Reduces R debt in position
    function testPositionDebtReduction() public {
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

        uint256 aliceDebtBefore = positionManager.raftDebtToken().balanceOf(ALICE);
        assertGt(aliceDebtBefore, 0);

        vm.prank(ALICE);
        positionManager.managePosition(
            collateralToken, ALICE, 0, false, aliceDebtBefore / 10, false, 0, emptySignature
        );

        uint256 aliceDebtAfter = positionManager.raftDebtToken().balanceOf(ALICE);
        assertGt(aliceDebtAfter, 0);
        assertEq(aliceDebtAfter, 9 * aliceDebtBefore / 10);
    }

    // Decreases user RToken balance by correct amount
    function testUpdateRTokenBalance() public {
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

        uint256 aliceDebtBefore = positionManager.raftDebtToken().balanceOf(ALICE);
        assertGt(aliceDebtBefore, 0);

        uint256 aliceRTokenBalanceBefore = rToken.balanceOf(ALICE);
        assertGt(aliceRTokenBalanceBefore, 0);

        vm.prank(ALICE);
        positionManager.managePosition(
            collateralToken, ALICE, 0, false, aliceDebtBefore / 10, false, 0, emptySignature
        );

        uint256 aliceRTokenBalanceAfter = rToken.balanceOf(ALICE);
        assertEq(aliceRTokenBalanceAfter, aliceRTokenBalanceBefore - aliceDebtBefore / 10);
    }

    // Reverts if borrower has insufficient R balance to cover his debt repayment
    function testInsufficientRBalance() public {
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

        uint256 bobBalanceBefore = rToken.balanceOf(BOB);
        assertGt(bobBalanceBefore, 0);

        // Bob transfers all but 5 of his R to Carol
        vm.prank(BOB);
        rToken.transfer(CAROL, bobBalanceBefore - 5e18);

        // Confirm Bob's R balance has decreased to 5 R
        uint256 bobBalanceAfter = rToken.balanceOf(BOB);
        assertEq(bobBalanceAfter, 5e18);

        // Bob tries to repay 6 R
        vm.prank(BOB);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        positionManager.managePosition(collateralToken, BOB, 0, false, 6e18, false, 0, emptySignature);
    }
}
