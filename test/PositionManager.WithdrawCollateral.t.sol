// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20Indexable } from "../contracts/Interfaces/IERC20Indexable.sol";
import { IPositionManager } from "../contracts/Interfaces/IPositionManager.sol";
import { PositionManager } from "../contracts/PositionManager.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { PriceFeedTestnet } from "./mocks/PriceFeedTestnet.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";

contract PositionManagerWithdrawCollateralTest is TestSetup {
    uint256 public constant DEFAULT_PRICE = 200e18;

    PriceFeedTestnet public priceFeed;

    function setUp() public override {
        super.setUp();

        priceFeed = new PriceFeedTestnet();
        positionManager.addCollateralToken(collateralToken, priceFeed, splitLiquidationCollateral);

        collateralToken.mint(ALICE, 10e36);
        collateralToken.mint(BOB, 10e36);
        collateralToken.mint(CAROL, 10e36);
        collateralToken.mint(DAVE, 10e36);
    }

    // Reverts when withdrawal would leave position with ICR < MCR
    function testInvalidICR() public {
        // Alice creates a position and adds first collateral
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

        assertLt(
            PositionManagerUtils.getCurrentICR(positionManager, collateralToken, ALICE, price),
            (110 * MathUtils._100_PERCENT / 100)
        );

        uint256 collateralWithdrawAmount = 1;

        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(IPositionManager.NewICRLowerThanMCR.selector, MathUtils._100_PERCENT - 1)
        );
        positionManager.managePosition(
            collateralToken, ALICE, collateralWithdrawAmount, false, 0, false, 0, emptySignature
        );
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

        // Bob successfully withdraws some collateral
        vm.prank(BOB);
        positionManager.managePosition(collateralToken, BOB, 0.1 ether, false, 0, false, 0, emptySignature);

        // Carol with no active position attempts to withdraw
        vm.prank(CAROL);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        positionManager.managePosition(collateralToken, CAROL, 1 ether, false, 0, true, 0, emptySignature);
    }

    // Reverts when requested collateral withdrawal is > the position's collateral
    function testWithdrawAmountExceedsCollateral() public {
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
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: CAROL,
            icr: 2e18
        });
        vm.stopPrank();

        (IERC20Indexable raftCollateralToken,,) = positionManager.raftCollateralTokens(collateralToken);
        uint256 bobPositionCollateral = raftCollateralToken.balanceOf(BOB);
        uint256 carolPositionCollateral = raftCollateralToken.balanceOf(CAROL);

        // Carol withdraws exactly all her collateral
        vm.prank(CAROL);
        vm.expectRevert(abi.encodeWithSelector(IPositionManager.NewICRLowerThanMCR.selector, 0));
        positionManager.managePosition(
            collateralToken, CAROL, carolPositionCollateral, false, 0, false, 0, emptySignature
        );

        // Bob attempts to withdraw 1 wei more than his collateral
        vm.prank(BOB);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        positionManager.managePosition(
            collateralToken, BOB, bobPositionCollateral + 1, false, 0, false, 0, emptySignature
        );
    }

    // Succeeds when borrowing rate = 0% and withdrawal would bring the user's ICR < MCR
    function testBorrowingRateZeroWithdrawalLowersICR() public {
        assertEq(positionManager.getBorrowingRate(collateralToken), 0);

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 10e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: BOB,
            icr: (110 * MathUtils._100_PERCENT / 100)
        });
        vm.stopPrank();

        // Bob attempts to withdraws 1 wei, which would leave him with < 110% ICR.
        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPositionManager.NewICRLowerThanMCR.selector, (110 * MathUtils._100_PERCENT / 100) - 1
            )
        );
        positionManager.managePosition(collateralToken, BOB, 1, false, 0, false, 0, emptySignature);
    }

    // Reverts when borrowing rate > 0% and withdrawal would bring the user's ICR < MCR
    function testBorrowingRateNonZeroWithdrawalLowersICR() public {
        positionManager.setBorrowingSpread(collateralToken, positionManager.MAX_BORROWING_SPREAD() / 2);
        assertGt(positionManager.getBorrowingRate(collateralToken), 0);

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 10e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: BOB,
            icr: (110 * MathUtils._100_PERCENT / 100)
        });
        vm.stopPrank();
        /*
        // Bob attempts to withdraws 1 wei, which would leave him with < 110% ICR.
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(NewICRLowerThanMCR.selector, (110 * MathUtils._100_PERCENT / 100) - 1));
        positionManager.managePosition(1, false, 0, false, 0);*/
    }

    // Doesn’t allow a user to completely withdraw all collateral from their position (due to gas compensation)
    function testDisallowedFullWithdrawal() public {
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
            icr: 2e18
        });
        vm.stopPrank();

        (IERC20Indexable raftCollateralToken, IERC20Indexable raftDebtToken,) =
            positionManager.raftCollateralTokens(collateralToken);
        uint256 alicePositionCollateral = raftCollateralToken.balanceOf(ALICE);

        // Check position is active
        assertGt(raftDebtToken.balanceOf(ALICE), 0);

        // Alice attempts to withdraw all collateral
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPositionManager.NewICRLowerThanMCR.selector, 0));
        positionManager.managePosition(
            collateralToken, ALICE, alicePositionCollateral, false, 0, false, 0, emptySignature
        );
    }

    // Leaves the position active when the user withdraws less than all the collateral
    function testOpenPositionAfterPartialWithdrawal() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 2e18
        });
        vm.stopPrank();

        (, IERC20Indexable raftDebtToken,) = positionManager.raftCollateralTokens(collateralToken);
        // Check position is active
        assertGt(raftDebtToken.balanceOf(ALICE), 0);

        // Alice withdraws some collateral
        vm.prank(ALICE);
        positionManager.managePosition(collateralToken, ALICE, 1e17, false, 0, false, 0, emptySignature);

        // Check position is still active
        assertGt(raftDebtToken.balanceOf(ALICE), 0);
    }

    // Reduces the position's collateral by the correct amount
    function testPositionCollateralReduction() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 2e18
        });
        vm.stopPrank();

        (IERC20Indexable raftCollateralToken,,) = positionManager.raftCollateralTokens(collateralToken);
        uint256 alicePositionCollateralBefore = raftCollateralToken.balanceOf(ALICE);

        uint256 withdrawAmount = 1 ether;

        // Alice withdraws 1 ether
        vm.prank(ALICE);
        positionManager.managePosition(collateralToken, ALICE, withdrawAmount, false, 0, false, 0, emptySignature);

        // Check 1 ether remaining
        uint256 alicePositionCollateralAfter = raftCollateralToken.balanceOf(ALICE);

        assertEq(alicePositionCollateralAfter, alicePositionCollateralBefore - withdrawAmount);
    }

    // Reduces position manager's collateral by correct amount
    function testPositionManagerCollateralReduction() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 positionManagerBalance = collateralToken.balanceOf(address(positionManager));
        uint256 withdrawAmount = 1 ether;

        vm.prank(ALICE);
        positionManager.managePosition(collateralToken, ALICE, withdrawAmount, false, 0, false, 0, emptySignature);

        uint256 positionManagerBalanceAfter = collateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerBalanceAfter, positionManagerBalance - withdrawAmount);
    }

    // Sends the correct amount of collateral to the user
    function testCollateralTransfer() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            extraDebtAmount: 0,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 aliceBalanceBefore = collateralToken.balanceOf(ALICE);
        uint256 withdrawAmount = 1 ether;

        // Alice withdraws 1 ether
        vm.prank(ALICE);
        positionManager.managePosition(collateralToken, ALICE, withdrawAmount, false, 0, false, 0, emptySignature);

        uint256 aliceBalanceAfter = collateralToken.balanceOf(ALICE);
        assertEq(aliceBalanceAfter, aliceBalanceBefore + withdrawAmount);
    }
}
