// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IPositionManager } from "../contracts/Interfaces/IPositionManager.sol";
import { PositionManagerTester } from "./TestContracts/PositionManagerTester.sol";
import { IERC20Indexable } from "../contracts/Interfaces/IERC20Indexable.sol";
import { IRToken } from "../contracts/Interfaces/IRToken.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { PriceFeedTestnet } from "./TestContracts/PriceFeedTestnet.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";

contract PositionManagerOpenPositionTest is TestSetup {
    uint256 public constant DEFAULT_PRICE = 200e18;

    PriceFeedTestnet public priceFeed;
    PositionManagerTester public positionManager;
    IRToken public rToken;

    function setUp() public override {
        super.setUp();

        priceFeed = new PriceFeedTestnet();
        positionManager = new PositionManagerTester(
            splitLiquidationCollateral
        );
        rToken = positionManager.rToken();

        positionManager.addCollateralToken(collateralToken, priceFeed);

        collateralToken.mint(ALICE, 10e36);
        collateralToken.mint(BOB, 10e36);
        collateralToken.mint(CAROL, 10e36);
        collateralToken.mint(DAVE, 10e36);
        collateralToken.mint(EVE, 10e36);
        collateralToken.mint(FRANK, 10e36);
    }

    function testSuccessfulPositionOpening() public {
        uint256 aliceExtraRAmount = PositionManagerUtils.getNetBorrowingAmount(
            positionManager, positionManager.splitLiquidationCollateral().LOW_TOTAL_DEBT()
        );

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            maxFeePercentage: MathUtils._100_PERCENT,
            extraDebtAmount: aliceExtraRAmount,
            icr: 0,
            amount: 100e30,
            ethType: PositionManagerUtils.ETHType.WSTETH
        });
        vm.stopPrank();

        assertGt(positionManager.raftDebtToken().balanceOf(ALICE), 0);

        uint256 bobExtraRAmount = PositionManagerUtils.getNetBorrowingAmount(
            positionManager, positionManager.splitLiquidationCollateral().LOW_TOTAL_DEBT() + 47_789_898e22
        );

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            maxFeePercentage: MathUtils._100_PERCENT,
            extraDebtAmount: bobExtraRAmount,
            icr: 0,
            amount: 100e30,
            ethType: PositionManagerUtils.ETHType.WSTETH
        });
        vm.stopPrank();

        assertGt(positionManager.raftDebtToken().balanceOf(BOB), 0);
    }

    // Decays a non-zero base rate
    function testNonZeroBaseRateDecay() public {
        vm.startPrank(FRANK);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 10_000e18,
            icr: 10e18
        });
        vm.stopPrank();

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 20_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 30_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 40_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Artificially make base rate 5%
        positionManager.setBaseRate(5 * MathUtils._100_PERCENT / 100);
        positionManager.setLastFeeOpTimeToNow();

        uint256 baseRate1 = positionManager.baseRate();
        assertGt(baseRate1, 0);

        skip(2 hours);

        vm.startPrank(DAVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 37e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Check base rate has decreased
        uint256 baseRate2 = positionManager.baseRate();
        assertLt(baseRate2, baseRate1);

        skip(1 hours);

        vm.startPrank(EVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 12e18,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 baseRate3 = positionManager.baseRate();
        assertLt(baseRate3, baseRate2);
    }

    // Doesn't change base rate if it is already zero
    function testUnchangedZeroBaseRate() public {
        vm.startPrank(FRANK);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 10_000e18,
            icr: 10e18
        });
        vm.stopPrank();

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 20_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 30_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 40_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 baseRate = positionManager.baseRate();
        assertEq(baseRate, 0);

        skip(2 hours);

        vm.startPrank(DAVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 37e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Check base rate has decreased
        baseRate = positionManager.baseRate();
        assertEq(baseRate, 0);

        skip(1 hours);

        vm.startPrank(EVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 12e18,
            icr: 2e18
        });
        vm.stopPrank();

        baseRate = positionManager.baseRate();
        assertEq(baseRate, 0);
    }

    // lastFeeOpTime doesn't update if less time than decay interval has passed since the last fee operation
    function testSmallDecayIntervalSinceFeeOp() public {
        vm.startPrank(FRANK);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 10_000e18,
            icr: 10e18
        });
        vm.stopPrank();

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 20_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 30_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 40_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Artificially make base rate 5%
        positionManager.setBaseRate(5 * MathUtils._100_PERCENT / 100);
        positionManager.setLastFeeOpTimeToNow();

        uint256 lastFeeOpTime1 = positionManager.lastFeeOperationTime();

        vm.startPrank(DAVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 37e18,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 lastFeeOpTime2 = positionManager.lastFeeOperationTime();
        assertEq(lastFeeOpTime2, lastFeeOpTime1);

        skip(1 minutes);

        vm.startPrank(EVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 12e18,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 lastFeeOpTime3 = positionManager.lastFeeOperationTime();
        assertGt(lastFeeOpTime3, lastFeeOpTime2);
    }

    // Borrower can't grief the base rate and stop it decaying by issuing debt at higher frequency than the decay
    // granularity
    function testDebtIssuingHigherFrequency() public {
        vm.startPrank(FRANK);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 10_000e18,
            icr: 10e18
        });
        vm.stopPrank();

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 20_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 30_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 40_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Artificially make base rate 5%
        positionManager.setBaseRate(5 * MathUtils._100_PERCENT / 100);
        positionManager.setLastFeeOpTimeToNow();

        // Check baseRate is non-zero
        uint256 baseRate1 = positionManager.baseRate();
        assertGt(baseRate1, 0);

        skip(59 minutes);

        // Assume borrower also owns accounts Dave and Eve
        // Borrower triggers a fee, before decay interval has passed
        vm.startPrank(DAVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 1e18,
            icr: 2e18
        });
        vm.stopPrank();

        skip(1 minutes);

        // Borrower triggers another fee
        vm.startPrank(EVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 1e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Check base rate has decreased even though Borrower tried to stop it decaying
        uint256 baseRate2 = positionManager.baseRate();
        assertLt(baseRate2, baseRate1);
    }

    // Borrowing at non-zero base rate sends R fee to fee recipient
    function testSendingFeesToFeeRecipient() public {
        address feeRecipient = positionManager.feeRecipient();

        skip(365 days);

        uint256 feeRecipientRBalanceBefore = rToken.balanceOf(feeRecipient);
        assertEq(feeRecipientRBalanceBefore, 0);

        vm.startPrank(EVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 10_000e18,
            icr: 10e18
        });
        vm.stopPrank();

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 20_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 30_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 40_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Artificially make base rate 5%
        positionManager.setBaseRate(5 * MathUtils._100_PERCENT / 100);
        positionManager.setLastFeeOpTimeToNow();

        skip(2 hours);

        vm.startPrank(DAVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 37e18,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 feeRecipientRBalanceAfter = rToken.balanceOf(feeRecipient);
        assertGt(feeRecipientRBalanceAfter, feeRecipientRBalanceBefore);
    }

    // reverts when position's ICR < MCR
    function testInvalidICR() public {
        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 5000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 5000e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Bob attempts to open a 109% ICR position
        vm.startPrank(BOB);
        uint256 bobICR = 109 * MathUtils._100_PERCENT / 100;
        (uint256 debtAmount,, uint256 amount) =
            PositionManagerUtils.getOpenPositionSetupValues(positionManager, priceFeed, 0, bobICR, 0);
        collateralToken.approve(address(positionManager), amount);
        vm.expectRevert(abi.encodeWithSelector(IPositionManager.NewICRLowerThanMCR.selector, bobICR));
        positionManager.managePosition(collateralToken, amount, true, debtAmount, true, MathUtils._100_PERCENT);
        vm.stopPrank();
    }

    // Creates a new position and assigns the correct collateral and debt amount
    function testPositionCollateralDebtAmount() public {
        (IERC20Indexable raftCollateralToken,) = positionManager.raftCollateralTokens(collateralToken);
        uint256 collateralBefore = raftCollateralToken.balanceOf(address(this));
        uint256 debtBefore = positionManager.raftDebtToken().balanceOf(address(this));

        assertEq(collateralBefore, 0);
        assertEq(debtBefore, 0);

        uint256 debtAmount = positionManager.splitLiquidationCollateral().LOW_TOTAL_DEBT();

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 0,
            icr: 0,
            amount: 100 ether
        });
        vm.stopPrank();

        uint256 collateralAfter = raftCollateralToken.balanceOf(ALICE);
        uint256 debtAfter = positionManager.raftDebtToken().balanceOf(ALICE);
        uint256 expectedDebt = PositionManagerUtils.getAmountWithBorrowingFee(positionManager, debtAmount);

        assertGt(collateralAfter, 0);
        assertGt(debtAfter, 0);
        assertEq(debtAfter, expectedDebt);
    }

    // Increases the position manager's collateral token balance by correct amount
    function testPositionManagerCollateralBalance() public {
        uint256 positionManagerCollateralBefore = collateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerCollateralBefore, 0);

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 5000e18,
            icr: 2e18
        });
        vm.stopPrank();

        (IERC20Indexable raftCollateralToken,) = positionManager.raftCollateralTokens(collateralToken);
        uint256 alicePositionCollateral = raftCollateralToken.balanceOf(ALICE);
        uint256 positionManagerCollateralAfter = collateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerCollateralAfter, alicePositionCollateral);
    }

    // Allows a user to open a position, then close it, then re-open it
    function testPositionReopening() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 5000e18,
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

        assertGt(positionManager.raftDebtToken().balanceOf(ALICE), 0);

        // To compensate borrowing fees
        vm.prank(address(positionManager));
        rToken.mint(ALICE, 10_000e18);

        (IERC20Indexable raftCollateralToken,) = positionManager.raftCollateralTokens(collateralToken);
        uint256 alicePositionCollateral = raftCollateralToken.balanceOf(ALICE);
        uint256 alicePositionDebt = positionManager.raftDebtToken().balanceOf(ALICE);

        vm.prank(ALICE);
        positionManager.managePosition(
            collateralToken, alicePositionCollateral, false, alicePositionDebt, false, MathUtils._100_PERCENT
        );

        assertEq(positionManager.raftDebtToken().balanceOf(ALICE), 0);

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 5000e18,
            icr: 2e18
        });
        vm.stopPrank();

        assertGt(positionManager.raftDebtToken().balanceOf(ALICE), 0);
    }

    // Increases the position's R debt and user's R token balance by the correct amounts
    function testPositionDebtUserBalanceIncrease() public {
        uint256 aliceDebtBefore = positionManager.raftDebtToken().balanceOf(ALICE);
        uint256 aliceRTokenBalanceBefore = rToken.balanceOf(ALICE);
        assertEq(aliceDebtBefore, 0);
        assertEq(aliceRTokenBalanceBefore, 0);

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 10_000e18,
            icr: 0,
            amount: 100 ether
        });
        vm.stopPrank();

        uint256 aliceDebtAfter = positionManager.raftDebtToken().balanceOf(ALICE);
        uint256 aliceRTokenBalanceAfter = rToken.balanceOf(ALICE);
        assertGt(aliceDebtAfter, 10_000e18);
        assertGt(aliceRTokenBalanceAfter, 10_000e18);
    }
}
