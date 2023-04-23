// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20Indexable } from "../contracts/Interfaces/IERC20Indexable.sol";
import { IPositionManager } from "../contracts/Interfaces/IPositionManager.sol";
import { PositionManager } from "../contracts/PositionManager.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { PriceFeedTestnet } from "./TestContracts/PriceFeedTestnet.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";

contract PositionManagerWithdrawCollateralTest is TestSetup {
    uint256 public constant DEFAULT_PRICE = 200e18;

    PriceFeedTestnet public priceFeed;
    IPositionManager public positionManager;

    function setUp() public override {
        super.setUp();

        priceFeed = new PriceFeedTestnet();
        positionManager = new PositionManager(
            splitLiquidationCollateral
        );
        positionManager.addCollateralToken(collateralToken, priceFeed);

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

        assertLt(PositionManagerUtils.getCurrentICR(positionManager, collateralToken, ALICE, price), MathUtils.MCR);

        uint256 collateralTopUpAmount = 1;

        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), collateralTopUpAmount);
        vm.expectRevert(abi.encodeWithSelector(IPositionManager.NewICRLowerThanMCR.selector, MathUtils._100_PERCENT));
        positionManager.managePosition(collateralToken, collateralTopUpAmount, true, 0, false, 0);
        vm.stopPrank();
    }

    // Reverts when calling address does not have active position
    function testNoActivePosition() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 10_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            extraDebtAmount: 10_000e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Bob successfully withdraws some collateral
        vm.prank(BOB);
        positionManager.managePosition(collateralToken, 0.1 ether, false, 0, false, 0);

        // Carol with no active position attempts to withdraw
        vm.prank(CAROL);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        positionManager.managePosition(collateralToken, 1 ether, false, 0, false, 0);
    }

    // Reverts when requested collateral withdrawal is > the position's collateral
    function testWithdrawAmountExceedsCollateral() public {
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

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        (IERC20Indexable raftCollateralToken,) = positionManager.raftCollateralTokens(collateralToken);
        uint256 bobPositionCollateral = raftCollateralToken.balanceOf(BOB);
        uint256 carolPositionCollateral = raftCollateralToken.balanceOf(CAROL);

        // Carol withdraws exactly all her collateral
        vm.prank(CAROL);
        vm.expectRevert(abi.encodeWithSelector(IPositionManager.NewICRLowerThanMCR.selector, 0));
        positionManager.managePosition(collateralToken, carolPositionCollateral, false, 0, false, 0);

        // Bob attempts to withdraw 1 wei more than his collateral
        vm.prank(BOB);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        positionManager.managePosition(collateralToken, bobPositionCollateral + 1, false, 0, false, 0);
    }

    // Succeeds when borrowing rate = 0% and withdrawal would bring the user's ICR < MCR
    function testBorrowingRateZeroWithdrawalLowersICR() public {
        assertEq(positionManager.getBorrowingRate(), 0);

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
            icr: MathUtils.MCR
        });
        vm.stopPrank();

        // Bob attempts to withdraws 1 wei, which would leave him with < 110% ICR.
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IPositionManager.NewICRLowerThanMCR.selector, MathUtils.MCR - 1));
        positionManager.managePosition(collateralToken, 1, false, 0, false, 0);
    }

    // Reverts when borrowing rate > 0% and withdrawal would bring the user's ICR < MCR
    function testBorrowingRateNonZeroWithdrawalLowersICR() public {
        positionManager.setBorrowingSpread(positionManager.MAX_BORROWING_SPREAD() / 2);
        assertGt(positionManager.getBorrowingRate(), 0);

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
            icr: MathUtils.MCR
        });
        vm.stopPrank();
        /*
        // Bob attempts to withdraws 1 wei, which would leave him with < 110% ICR.
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(NewICRLowerThanMCR.selector, MathUtils.MCR - 1));
        positionManager.managePosition(1, false, 0, false, 0);*/
    }

    // Doesn’t allow a user to completely withdraw all collateral from their position (due to gas compensation)
    function testDisallowedFullWithdrawal() public {
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

        (IERC20Indexable raftCollateralToken,) = positionManager.raftCollateralTokens(collateralToken);
        uint256 alicePositionCollateral = raftCollateralToken.balanceOf(ALICE);

        // Check position is active
        assertGt(positionManager.raftDebtToken().balanceOf(ALICE), 0);

        // Alice attempts to withdraw all collateral
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPositionManager.NewICRLowerThanMCR.selector, 0));
        positionManager.managePosition(collateralToken, alicePositionCollateral, false, 0, false, 0);
    }

    // Leaves the position active when the user withdraws less than all the collateral
    function testOpenPositionAfterPartialWithdrawal() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        // Check position is active
        assertGt(positionManager.raftDebtToken().balanceOf(ALICE), 0);

        // Alice withdraws some collateral
        vm.prank(ALICE);
        positionManager.managePosition(collateralToken, 1e17, false, 0, false, 0);

        // Check position is still active
        assertGt(positionManager.raftDebtToken().balanceOf(ALICE), 0);
    }

    // Reduces the position's collateral by the correct amount
    function testPositionCollateralReduction() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        (IERC20Indexable raftCollateralToken,) = positionManager.raftCollateralTokens(collateralToken);
        uint256 alicePositionCollateralBefore = raftCollateralToken.balanceOf(ALICE);

        uint256 withdrawAmount = 1 ether;

        // Alice withdraws 1 ether
        vm.prank(ALICE);
        positionManager.managePosition(collateralToken, withdrawAmount, false, 0, false, 0);

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
            icr: 2e18
        });
        vm.stopPrank();

        uint256 positionManagerBalance = collateralToken.balanceOf(address(positionManager));
        uint256 withdrawAmount = 1 ether;

        vm.prank(ALICE);
        positionManager.managePosition(collateralToken, withdrawAmount, false, 0, false, 0);

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
            extraDebtAmount: 0,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 aliceBalanceBefore = collateralToken.balanceOf(ALICE);
        uint256 withdrawAmount = 1 ether;

        // Alice withdraws 1 ether
        vm.prank(ALICE);
        positionManager.managePosition(collateralToken, withdrawAmount, false, 0, false, 0);

        uint256 aliceBalanceAfter = collateralToken.balanceOf(ALICE);
        assertEq(aliceBalanceAfter, aliceBalanceBefore + withdrawAmount);
    }
}
