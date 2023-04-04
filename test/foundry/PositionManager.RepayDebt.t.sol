// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../../contracts/PositionManager.sol";
import "../TestContracts/PriceFeedTestnet.sol";
import "../TestContracts/WstETHTokenMock.sol";
import "./utils/PositionManagerUtils.sol";
import "./utils/TestSetup.t.sol";

contract PositionManagerRepayDebtTest is TestSetup {
    uint256 public constant POSITIONS_SIZE = 10;
    uint256 public constant LIQUIDATION_PROTOCOL_FEE = 0;
    uint256 public constant DEFAULT_PRICE = 200e18;

    PriceFeedTestnet public priceFeed;
    IPositionManager public positionManager;
    IRToken public rToken;

    function setUp() public {
        priceFeed = new PriceFeedTestnet();
        collateralToken = new WstETHTokenMock();
        positionManager = new PositionManager(
            priceFeed,
            collateralToken,
            POSITIONS_SIZE,
            LIQUIDATION_PROTOCOL_FEE
        );
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

        // Price drops
        priceFeed.setPrice(100e18);
        uint256 price = priceFeed.getPrice();

        assertLt(positionManager.getCurrentICR(ALICE, price), MathUtils.MCR);

        uint256 repaymentAmount = 1;

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(NetDebtBelowMinimum.selector, MathUtils.MIN_NET_DEBT - 1));
        positionManager.repayR(repaymentAmount, ALICE, ALICE);
    }

    // Succeeds when it would leave position with net debt >= minimum net debt
    function testSuccessfulRepayAboveNetDebtMin() public {
        // Make the R request 2 wei above min net debt to correct for floor division, and make
        // net debt = min net debt + 1 wei
        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), 100e30);
        positionManager.openPosition(
            MathUtils._100pct,
            PositionManagerUtils.getNetBorrowingAmount(positionManager, MathUtils.MIN_NET_DEBT + 2),
            ALICE,
            ALICE,
            100e30
        );
        vm.stopPrank();

        vm.prank(ALICE);
        positionManager.repayR(1, ALICE, ALICE);

        vm.startPrank(BOB);
        collateralToken.approve(address(positionManager), 100e30);
        positionManager.openPosition(MathUtils._100pct, 20e25, BOB, BOB, 100e30);
        vm.stopPrank();

        vm.prank(BOB);
        positionManager.repayR(19e25, BOB, BOB);
    }

    // Reverts when borrowing rate = 0% and it would leave position with net debt < minimum net debt
    function testRevertNetDebtBelowMinWhenBorrowingRateZero() public {
        assertEq(positionManager.getBorrowingRate(), 0);

        // Make the R request 1 wei above min net debt to correct for floor division, and make
        // net debt = min net debt + 1 wei
        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), 100e30);
        positionManager.openPosition(
            MathUtils._100pct,
            PositionManagerUtils.getNetBorrowingAmount(positionManager, MathUtils.MIN_NET_DEBT + 1),
            ALICE,
            ALICE,
            100e30
        );
        vm.stopPrank();

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(NetDebtBelowMinimum.selector, MathUtils.MIN_NET_DEBT - 1));
        positionManager.repayR(2, ALICE, ALICE);
    }

    // Reverts when borrowing rate > 0% and it would leave position with net debt < minimum net debt
    function testRevertNetDebtBelowMinWhenBorrowingRateNonZero() public {
        positionManager.setBorrowingSpread(positionManager.MAX_BORROWING_SPREAD() / 2);
        assertGt(positionManager.getBorrowingRate(), 0);

        // Make the R request 1 wei above min net debt to correct for floor division, and make
        // net debt = min net debt + 1 wei
        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), 100e30);
        positionManager.openPosition(
            MathUtils._100pct,
            PositionManagerUtils.getNetBorrowingAmount(positionManager, MathUtils.MIN_NET_DEBT + 1),
            ALICE,
            ALICE,
            100e30
        );
        vm.stopPrank();

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(NetDebtBelowMinimum.selector, MathUtils.MIN_NET_DEBT - 1));
        positionManager.repayR(2, ALICE, ALICE);
    }

    // Reverts when calling address does not have active position
    function testNoActivePosition() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 10000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 10000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.prank(BOB);
        positionManager.repayR(10e18, BOB, BOB);

        // Carol with no active position attempts to repay R
        vm.prank(CAROL);
        vm.expectRevert(PositionManagerPositionNotActive.selector);
        positionManager.repayR(10e18, CAROL, CAROL);
    }

    // Reverts when attempted repayment is > the debt of the position
    function testUnsuccessfulRepayLargerThanDebt() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 10000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 10000e18,
            icr: 2e18
        });
        vm.stopPrank();

        (uint256 aliceDebt,,,) = positionManager.getEntireDebtAndColl(ALICE);

        // Bob successfully repays some R
        vm.prank(BOB);
        positionManager.repayR(10e18, BOB, BOB);

        // Alice attempts to repay more than her debt
        vm.prank(ALICE);
        vm.expectRevert(stdError.arithmeticError);
        positionManager.repayR(aliceDebt + 1e18, ALICE, ALICE);
    }

    // Reduces R debt in position
    function testPositionDebtReduction() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 10000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 10000e18,
            icr: 2e18
        });
        vm.stopPrank();

        (uint256 aliceDebtBefore,,,) = positionManager.getEntireDebtAndColl(ALICE);
        assertGt(aliceDebtBefore, 0);

        vm.prank(ALICE);
        positionManager.repayR(aliceDebtBefore / 10, ALICE, ALICE);

        (uint256 aliceDebtAfter,,,) = positionManager.getEntireDebtAndColl(ALICE);
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
            extraRAmount: 10000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 10000e18,
            icr: 2e18
        });
        vm.stopPrank();

        (uint256 aliceDebtBefore,,,) = positionManager.getEntireDebtAndColl(ALICE);
        assertGt(aliceDebtBefore, 0);

        uint256 aliceRTokenBalanceBefore = rToken.balanceOf(ALICE);
        assertGt(aliceRTokenBalanceBefore, 0);

        vm.prank(ALICE);
        positionManager.repayR(aliceDebtBefore / 10, ALICE, ALICE);

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
            extraRAmount: 10000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraRAmount: 10000e18,
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
        positionManager.repayR(6e18, BOB, BOB);
    }
}
