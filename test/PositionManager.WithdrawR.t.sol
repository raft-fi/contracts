// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {MathUtils} from "../contracts/Dependencies/MathUtils.sol";
import {IRToken} from "../contracts/Interfaces/IRToken.sol";
import {IPositionManager} from "../contracts/Interfaces/IPositionManager.sol";
import {PositionManagerTester} from "./TestContracts/PositionManagerTester.sol";
import {PriceFeedTestnet} from "./TestContracts/PriceFeedTestnet.sol";
import {PositionManagerUtils} from "./utils/PositionManagerUtils.sol";
import {TestSetup} from "./utils/TestSetup.t.sol";

contract PositionManagerWithdrawRTest is TestSetup {
    uint256 public constant DEFAULT_PRICE = 200e18;

    PriceFeedTestnet public priceFeed;
    PositionManagerTester public positionManager;
    IRToken public rToken;

    function setUp() public override {
        super.setUp();

        priceFeed = new PriceFeedTestnet();
        positionManager = new PositionManagerTester(
            new address[](0),
            splitLiquidationCollateral
        );
        positionManager.addCollateralToken(collateralToken, priceFeed);

        rToken = positionManager.rToken();

        collateralToken.mint(ALICE, 10e36);
        collateralToken.mint(BOB, 10e36);
        collateralToken.mint(CAROL, 10e36);
        collateralToken.mint(DAVE, 10e36);
        collateralToken.mint(EVE, 10e36);
        collateralToken.mint(FRANK, 10e36);
    }

    // Reverts when withdrawal would leave position with ICR < MCR
    function testInvalidICR() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 10e18
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: MathUtils.MCR
        });
        vm.stopPrank();

        vm.prank(CAROL);
        vm.expectRevert(abi.encodeWithSelector(IPositionManager.NewICRLowerThanMCR.selector, MathUtils.MCR - 1));
        positionManager.managePosition(collateralToken, 0, false, 1, true, MathUtils._100_PERCENT);

        // Price drops
        priceFeed.setPrice(100e18);
        uint256 price = priceFeed.getPrice();

        assertLt(positionManager.getCurrentICR(collateralToken, ALICE, price), MathUtils.MCR);

        uint256 withdrawalAmount = 1;

        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(IPositionManager.NewICRLowerThanMCR.selector, MathUtils._100_PERCENT - 1)
        );
        positionManager.managePosition(collateralToken, 0, false, withdrawalAmount, true, MathUtils._100_PERCENT);
    }

    // Decays a non-zero base rate
    function testNonZeroBaseRateDecay() public {
        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 10e18
        });
        vm.stopPrank();

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 20e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 20e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(DAVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 20e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(EVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 20e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Artificially set base rate to 5%
        positionManager.setBaseRate(5 * MathUtils._100_PERCENT / 100);

        // Check base rate is now non-zero
        uint256 baseRate1 = positionManager.baseRate();
        assertGt(baseRate1, 0);

        skip(2 hours);

        // Dave withdraws R
        vm.prank(DAVE);
        positionManager.managePosition(collateralToken, 0, false, 1e18, true, MathUtils._100_PERCENT);

        // Check base rate has decreased
        uint256 baseRate2 = positionManager.baseRate();
        assertLt(baseRate2, baseRate1);

        skip(1 hours);

        // Eve withdraws R
        vm.prank(EVE);
        positionManager.managePosition(collateralToken, 0, false, 1e18, true, MathUtils._100_PERCENT);

        uint256 baseRate3 = positionManager.baseRate();
        assertLt(baseRate3, baseRate2);
    }

    // Reverts if max fee > 100%
    function testInvalidMaxFee() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 10e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 20e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 40e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(DAVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 40e18,
            icr: 2e18
        });

        vm.expectRevert(IPositionManager.InvalidMaxFeePercentage.selector);
        positionManager.managePosition(collateralToken, 0, false, 1e18, true, MathUtils._100_PERCENT + 1);
    }

    // Reverts if fee exceeds max fee percentage
    function testFeeExceedsMaxFeePercentage() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 60e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 60e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 70e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(DAVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 80e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(EVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 180e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Artificially make base rate 5%
        positionManager.setBaseRate(5 * MathUtils._100_PERCENT / 100);
        positionManager.setLastFeeOpTimeToNow();

        uint256 baseRate = positionManager.baseRate();

        // 100%: 1e18,  10%: 1e17,  1%: 1e16,  0.1%: 1e15
        // 5%: 5e16
        // 0.5%: 5e15
        // actual: 0.5%, 5e15

        // rFee:                     15000000558793542
        // absolute _fee:            15000000558793542
        // actual feePercentage:      5000000186264514
        // user's _maxFeePercentage: 49999999999999999

        uint256 maxFee = 5 * MathUtils._100_PERCENT / 100 - 1;
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPositionManager.FeeExceedsMaxFee.selector, 0.15e18, 3e18, maxFee));
        positionManager.managePosition(collateralToken, 0, false, 3e18, true, maxFee);

        baseRate = positionManager.baseRate();
        assertEq(baseRate, 5 * MathUtils._100_PERCENT / 100);

        // Attempt with max fee = 1%
        maxFee = MathUtils._100_PERCENT / 100;
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IPositionManager.FeeExceedsMaxFee.selector, 0.05e18, 1e18, maxFee));
        positionManager.managePosition(collateralToken, 0, false, 1e18, true, maxFee);

        baseRate = positionManager.baseRate();
        assertEq(baseRate, 5 * MathUtils._100_PERCENT / 100);

        // Attempt with max fee = 3.754%
        maxFee = 3754 * MathUtils._100_PERCENT / 100000;
        vm.prank(CAROL);
        vm.expectRevert(abi.encodeWithSelector(IPositionManager.FeeExceedsMaxFee.selector, 0.05e18, 1e18, maxFee));
        positionManager.managePosition(collateralToken, 0, false, 1e18, true, maxFee);

        baseRate = positionManager.baseRate();
        assertEq(baseRate, 5 * MathUtils._100_PERCENT / 100);

        // Attempt with max fee = 0.5%
        maxFee = 5 * MathUtils._100_PERCENT / 1000;
        vm.prank(DAVE);
        vm.expectRevert(abi.encodeWithSelector(IPositionManager.FeeExceedsMaxFee.selector, 0.05e18, 1e18, maxFee));
        positionManager.managePosition(collateralToken, 0, false, 1e18, true, maxFee);
    }

    // Succeeds when fee is less than max fee percentage
    function testValidMaxFeePercentage() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 60e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 60e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 70e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(DAVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 80e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(EVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 180e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Artificially make baseRate 5%
        positionManager.setBaseRate(5 * MathUtils._100_PERCENT / 100);
        positionManager.setLastFeeOpTimeToNow();

        uint256 baseRate = positionManager.baseRate();
        assertEq(baseRate, 5 * MathUtils._100_PERCENT / 100);

        // Attempt with max fee > 5%
        vm.prank(ALICE);
        positionManager.managePosition(collateralToken, 0, false, 1e18, true, 5 * MathUtils._100_PERCENT / 100 + 1);

        baseRate = positionManager.baseRate();
        assertEq(baseRate, 5 * MathUtils._100_PERCENT / 100);

        // Attempt with max fee = 5%
        vm.prank(BOB);
        positionManager.managePosition(collateralToken, 0, false, 1e18, true, 5 * MathUtils._100_PERCENT / 100);

        baseRate = positionManager.baseRate();
        assertEq(baseRate, 5 * MathUtils._100_PERCENT / 100);

        // Attempt with max fee = 10%
        vm.prank(CAROL);
        positionManager.managePosition(collateralToken, 0, false, 1e18, true, 1 * MathUtils._100_PERCENT / 10);

        baseRate = positionManager.baseRate();
        assertEq(baseRate, 5 * MathUtils._100_PERCENT / 100);

        // Attempt with max fee = 37.659%
        vm.prank(DAVE);
        positionManager.managePosition(collateralToken, 0, false, 1e18, true, 37659 * MathUtils._100_PERCENT / 100000);

        // Attempt with max fee = 100%
        vm.prank(EVE);
        positionManager.managePosition(collateralToken, 0, false, 1e18, true, MathUtils._100_PERCENT);
    }

    // Doesn't change base rate if it is already zero
    function testKeepingZeroBaseRate() public {
        vm.startPrank(FRANK);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 10e18
        });
        vm.stopPrank();

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 30e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 40e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 50e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(DAVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 50e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(EVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 50e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Check base rate is zero
        uint256 baseRate1 = positionManager.baseRate();
        assertEq(baseRate1, 0);

        skip(2 hours);

        // Dave withdraws R
        vm.prank(DAVE);
        positionManager.managePosition(collateralToken, 0, false, 37e18, true, MathUtils._100_PERCENT);

        // Check base rate is still 0
        uint256 baseRate2 = positionManager.baseRate();
        assertEq(baseRate2, 0);

        skip(1 hours);

        // Eve opens position
        vm.prank(EVE);
        positionManager.managePosition(collateralToken, 0, false, 12e18, true, MathUtils._100_PERCENT);

        uint256 baseRate3 = positionManager.baseRate();
        assertEq(baseRate3, 0);
    }

    // lastFeeOpTime doesn't update if less time than decay interval has passed since the last fee operation
    function testSmallDecayIntervalSinceFeeOp() public {
        vm.startPrank(DAVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 10e18
        });
        vm.stopPrank();

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 30e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 40e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 50e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Artificially make baseRate 5%
        positionManager.setBaseRate(5 * MathUtils._100_PERCENT / 100);
        positionManager.setLastFeeOpTimeToNow();

        // Check base rate is now non-zero
        uint256 baseRate1 = positionManager.baseRate();
        assertGt(baseRate1, 0);

        uint256 lastFeeOpTime1 = positionManager.lastFeeOperationTime();

        skip(10 seconds);

        // Borrower Carol triggers a fee
        vm.prank(CAROL);
        positionManager.managePosition(collateralToken, 0, false, 1e18, true, MathUtils._100_PERCENT);

        uint256 lastFeeOpTime2 = positionManager.lastFeeOperationTime();

        // Check that the last fee operation time did not update, as borrower D's debt issuance occurred
        // since before minimum interval had passed
        assertEq(lastFeeOpTime2, lastFeeOpTime1);

        skip(1 minutes);

        // Borrower Carol triggers a fee
        vm.prank(CAROL);
        positionManager.managePosition(collateralToken, 0, false, 1e18, true, MathUtils._100_PERCENT);

        uint256 lastFeeOpTime3 = positionManager.lastFeeOperationTime();

        // Check that the last fee operation time DID update, as borrower's debt issuance occurred
        // after minimum interval had passed
        assertGt(lastFeeOpTime3, lastFeeOpTime1);
    }

    // Borrower can't grief the base rate and stop it decaying by issuing debt at higher frequency than the decay
    // granularity
    function testDebtIssuingHigherFrequency() public {
        vm.startPrank(DAVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 10e18
        });
        vm.stopPrank();

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 30e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 40e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 50e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Artificially make base rate 5%
        positionManager.setBaseRate(5 * MathUtils._100_PERCENT / 100);
        positionManager.setLastFeeOpTimeToNow();

        // Check base rate is now non-zero
        uint256 baseRate1 = positionManager.baseRate();
        assertGt(baseRate1, 0);

        skip(30 seconds);

        // Borrower Carol triggers a fee, before decay interval has passed
        vm.prank(CAROL);
        positionManager.managePosition(collateralToken, 0, false, 1e18, true, MathUtils._100_PERCENT);

        skip(30 seconds);

        // Borrower Carol triggers another fee
        vm.prank(CAROL);
        positionManager.managePosition(collateralToken, 0, false, 1e18, true, MathUtils._100_PERCENT);

        // Check base rate has decreased even though borrower tried to stop it decaying
        uint256 baseRate2 = positionManager.baseRate();
        assertLt(baseRate2, baseRate1);
    }

    // Borrowing at non-zero base rate sends R fee to fee recipient
    function testSendingFeeToFeeRecipient() public {
        address feeRecipient = positionManager.feeRecipient();

        skip(365 days);

        uint256 feeRecipientRBalanceBefore = rToken.balanceOf(feeRecipient);

        vm.startPrank(EVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 10e18
        });
        vm.stopPrank();

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 30e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 40e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 50e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(DAVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 50e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Artificially make base rate 5%
        positionManager.setBaseRate(5 * MathUtils._100_PERCENT / 100);
        positionManager.setLastFeeOpTimeToNow();

        // Check base rate is now non-zero
        uint256 baseRate1 = positionManager.baseRate();
        assertGt(baseRate1, 0);

        skip(2 hours);

        uint256 daveBalanceBefore = rToken.balanceOf(DAVE);
        uint256 withdrawAmount = 37e18;

        // Dave withdraws R
        vm.prank(DAVE);
        positionManager.managePosition(collateralToken, 0, false, withdrawAmount, true, MathUtils._100_PERCENT);

        // Check fee recipient's R balance after has increased
        uint256 feeRecipientRBalanceAfter = rToken.balanceOf(feeRecipient);
        assertGt(feeRecipientRBalanceAfter, feeRecipientRBalanceBefore);

        // Check Dave's R balance now equals their initial balance plus request R
        uint256 daveBalanceAfter = rToken.balanceOf(DAVE);
        assertEq(daveBalanceAfter, daveBalanceBefore + withdrawAmount);
    }

    // Borrowing at non-zero base records drawn debt + fee
    function testSavedDrawnDebtAndFee() public {
        skip(365 days);

        vm.startPrank(EVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 10e18
        });
        vm.stopPrank();

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 30e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 40e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 50e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(DAVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 50e18,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 daveDebtBefore = positionManager.raftDebtToken().balanceOf(DAVE);

        // Artificially make baseRate 5%
        positionManager.setBaseRate(5 * MathUtils._100_PERCENT / 100);
        positionManager.setLastFeeOpTimeToNow();

        // Check base rate is now non-zero
        uint256 baseRate = positionManager.baseRate();
        assertGt(baseRate, 0);

        skip(2 hours);

        // Dave withdraws R
        uint256 daveWithdrawal = 37e18;
        vm.prank(DAVE);
        positionManager.managePosition(collateralToken, 0, false, daveWithdrawal, true, MathUtils._100_PERCENT);

        uint256 daveDebtAfter = positionManager.raftDebtToken().balanceOf(DAVE);

        // Check debt is equal to initial debt + withdrawal + emitted fee
        uint256 fee = positionManager.getBorrowingFee(daveWithdrawal);
        assertEq(daveDebtAfter, daveDebtBefore + daveWithdrawal + fee);
    }

    // Borrowing at non-zero base rate sends requested amount to the user
    function testWithdrawalNonZeroBaseRate() public {
        address feeRecipient = positionManager.feeRecipient();

        skip(365 days);

        vm.startPrank(EVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 10e18
        });
        vm.stopPrank();

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 30e18,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 feeRecipientRBalanceBefore = rToken.balanceOf(feeRecipient);
        assertEq(feeRecipientRBalanceBefore, 0);

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 40e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 50e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(DAVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 50e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Artificially make base rate 5%
        positionManager.setBaseRate(5 * MathUtils._100_PERCENT / 100);
        positionManager.setLastFeeOpTimeToNow();

        uint256 baseRate = positionManager.baseRate();
        assertGt(baseRate, 0);

        skip(2 hours);

        uint256 daveRBalanceBefore = rToken.balanceOf(DAVE);

        // Dave withdraws R
        uint256 daveWithdrawal = 37e18;
        vm.prank(DAVE);
        positionManager.managePosition(collateralToken, 0, false, daveWithdrawal, true, MathUtils._100_PERCENT);

        // Check fee recipient's R balance has increased
        uint256 feeRecipientRBalanceAfter = rToken.balanceOf(feeRecipient);
        assertGt(feeRecipientRBalanceAfter, feeRecipientRBalanceBefore);

        // Check D's R balance now equals their initial balance plus requested R
        uint256 daveRBalanceAfter = rToken.balanceOf(DAVE);
        assertEq(daveRBalanceAfter, daveRBalanceBefore + daveWithdrawal);
    }

    // Borrowing at zero base rate sends requested amount to the user
    function testWithdrawalZeroBaseRate() public {
        vm.startPrank(EVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 10e18
        });
        vm.stopPrank();

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 30e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 40e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 50e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(DAVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 50e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Check base rate is zero
        uint256 baseRate1 = positionManager.baseRate();
        assertEq(baseRate1, 0);

        skip(2 hours);

        uint256 daveRBalanceBefore = rToken.balanceOf(DAVE);

        // Dave withdraws R
        uint256 withdrawalAmount = 37e18;
        vm.prank(DAVE);
        positionManager.managePosition(collateralToken, 0, false, withdrawalAmount, true, MathUtils._100_PERCENT);

        // Check Dave's R balance now equals their requested R
        uint256 daveRBalanceAfter = rToken.balanceOf(DAVE);

        // Check Dave's position debt = Dave's R balance + liquidation reserve
        assertEq(daveRBalanceAfter, daveRBalanceBefore + withdrawalAmount);
    }

    // Reverts when calling address does not have active position
    function testNoActivePosition() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 10e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        // Bob successfully withdraws R
        vm.prank(BOB);
        positionManager.managePosition(collateralToken, 0, false, 1e18, true, MathUtils._100_PERCENT);

        // Carol with no active position attempts to withdraw R
        vm.prank(CAROL);
        vm.expectRevert(abi.encodeWithSelector(IPositionManager.NetDebtBelowMinimum.selector, 100e18));
        positionManager.managePosition(collateralToken, 0, false, 100e18, true, MathUtils._100_PERCENT);
    }

    // Reverts when requested withdrawal amount is zero R
    function testInvalidZeroWithdrawalAmount() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        // Bob successfully withdraws 1e-18 R
        vm.prank(BOB);
        positionManager.managePosition(collateralToken, 0, false, 1, true, MathUtils._100_PERCENT);

        // Alice attempts to withdraw 0 R
        vm.prank(ALICE);
        vm.expectRevert(IPositionManager.NoCollateralOrDebtChange.selector);
        positionManager.managePosition(collateralToken, 0, false, 0, true, MathUtils._100_PERCENT);
    }

    // Increases user's R token balance and the position's R debt by correct amount
    function testCorrectRTokenBalanceIncrease() public {
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

        uint256 aliceRTokenBalanceBefore = rToken.balanceOf(ALICE);
        assertGt(aliceRTokenBalanceBefore, 0);

        uint256 aliceDebtBefore = positionManager.raftDebtToken().balanceOf(ALICE);
        assertGt(aliceDebtBefore, 0);

        uint256 withdrawAmount = 10000e18;

        vm.prank(ALICE);
        positionManager.managePosition(collateralToken, 0, false, withdrawAmount, true, MathUtils._100_PERCENT);

        uint256 aliceRTokenBalanceAfter = rToken.balanceOf(ALICE);
        assertEq(aliceRTokenBalanceAfter, aliceRTokenBalanceBefore + withdrawAmount);

        uint256 aliceDebtAfter = positionManager.raftDebtToken().balanceOf(ALICE);
        assertApproxEqAbs(aliceDebtAfter, aliceDebtBefore + withdrawAmount, 10);
    }
}
