// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {
    IPositionManager,
    DelegateNotWhitelisted,
    BorrowingSpreadExceedsMaximum
} from "../contracts/Interfaces/IPositionManager.sol";
import {PositionManager} from "../contracts/PositionManager.sol";
import {MathUtils} from "../contracts/Dependencies/MathUtils.sol";
import {PriceFeedTestnet} from "./TestContracts/PriceFeedTestnet.sol";
import {PositionManagerUtils} from "./utils/PositionManagerUtils.sol";
import {TestSetup} from "./utils/TestSetup.t.sol";

contract PositionManagerTest is TestSetup {
    uint256 public constant POSITIONS_SIZE = 10;
    uint256 public constant LIQUIDATION_PROTOCOL_FEE = 0;

    PriceFeedTestnet public priceFeed;
    IPositionManager public positionManager;

    function setUp() public override {
        super.setUp();

        priceFeed = new PriceFeedTestnet();
        priceFeed.setPrice(1e18);
        positionManager = new PositionManager(
            priceFeed,
            collateralToken,
            POSITIONS_SIZE,
            LIQUIDATION_PROTOCOL_FEE,
            new address[](0)
        );

        collateralToken.mint(ALICE, 10e36);
        collateralToken.mint(BOB, 10e36);
    }

    // --- Delegates ---

    function testGlobalDelegates() public {
        address[] memory globalDelegates = new address[](1);
        globalDelegates[0] = address(BOB);
        collateralToken.mint(ALICE, 10 ether);
        PositionManager positionManager2 = new PositionManager(
            priceFeed,
            collateralToken,
            POSITIONS_SIZE,
            LIQUIDATION_PROTOCOL_FEE,
            globalDelegates
        );

        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager2,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 collateralTopUpAmount = 1 ether;
        uint256 debtAmount = collateralTopUpAmount / 10;

        vm.startPrank(BOB);
        collateralToken.approve(address(positionManager2), collateralTopUpAmount);

        uint256 borrowerDebtBefore = positionManager2.raftDebtToken().balanceOf(ALICE);
        uint256 borrowerCollBefore = positionManager2.raftCollateralToken().balanceOf(ALICE);
        uint256 borrowerRBalanceBefore = positionManager2.rToken().balanceOf(ALICE);
        uint256 borrowerCollateralBalanceBefore = collateralToken.balanceOf(ALICE);
        uint256 delegateRBalanceBefore = positionManager2.rToken().balanceOf(BOB);
        uint256 delegateCollateralBalanceBefore = collateralToken.balanceOf(BOB);
        positionManager2.managePosition(ALICE, collateralTopUpAmount, true, debtAmount, true, ALICE, ALICE, 0);
        uint256 borrowerRBalanceAfter = positionManager2.rToken().balanceOf(ALICE);
        uint256 borrowerCollateralBalanceAfter = collateralToken.balanceOf(ALICE);
        uint256 delegateRBalanceAfter = positionManager2.rToken().balanceOf(BOB);
        uint256 delegateCollateralBalanceAfter = collateralToken.balanceOf(BOB);
        uint256 borrowerDebtAfter = positionManager2.raftDebtToken().balanceOf(ALICE);
        uint256 borrowerCollAfter = positionManager2.raftCollateralToken().balanceOf(ALICE);

        uint256 delegateDebtAfter = positionManager2.raftDebtToken().balanceOf(BOB);
        uint256 delegateCollAfter = positionManager2.raftCollateralToken().balanceOf(BOB);

        assertEq(borrowerRBalanceAfter, borrowerRBalanceBefore + debtAmount);
        assertEq(borrowerCollateralBalanceAfter, borrowerCollateralBalanceBefore);
        assertEq(delegateRBalanceAfter, delegateRBalanceBefore);
        assertEq(delegateCollateralBalanceAfter, delegateCollateralBalanceBefore - collateralTopUpAmount);
        assertEq(borrowerDebtAfter - borrowerDebtBefore, debtAmount);
        assertEq(borrowerCollAfter - borrowerCollBefore, collateralTopUpAmount);
        assertEq(delegateDebtAfter, 0);
        assertEq(delegateCollAfter, 0);
    }

    function testIndividualDelegates() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        vm.prank(ALICE);
        positionManager.whitelistDelegate(BOB);

        uint256 collateralTopUpAmount = 1 ether;
        vm.startPrank(BOB);
        collateralToken.approve(address(positionManager), collateralTopUpAmount);
        positionManager.managePosition(ALICE, collateralTopUpAmount, true, 0, false, ALICE, ALICE, 0);
    }

    function testNonDelegateCannotManagePosition() public {
        uint256 collateralTopUpAmount = 1 ether;
        vm.startPrank(BOB);
        collateralToken.approve(address(positionManager), collateralTopUpAmount);

        vm.expectRevert(DelegateNotWhitelisted.selector);
        positionManager.managePosition(ALICE, collateralTopUpAmount, true, 0, false, ALICE, ALICE, 0);
    }

    function testIndividualDelegateCannotManageOtherPositions() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        vm.prank(CAROL);
        positionManager.whitelistDelegate(BOB);

        uint256 collateralTopUpAmount = 1 ether;
        vm.prank(ALICE);
        collateralToken.approve(address(positionManager), collateralTopUpAmount);

        vm.prank(BOB);
        vm.expectRevert(DelegateNotWhitelisted.selector);
        positionManager.managePosition(ALICE, collateralTopUpAmount, true, 0, false, ALICE, ALICE, 0);
    }

    // --- Borrowing Spread ---

    function testSetBorrowingSpread() public {
        positionManager.setBorrowingSpread(100);
        assertEq(positionManager.borrowingSpread(), 100);
    }

    function testUnauthorizedSetBorrowingSpread() public {
        vm.prank(ALICE);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        positionManager.setBorrowingSpread(100);
    }

    function testOutOfBoundsSetBorrowingSpread() public {
        uint256 maxBorrowingSpread = positionManager.MAX_BORROWING_SPREAD();
        vm.expectRevert(BorrowingSpreadExceedsMaximum.selector);
        positionManager.setBorrowingSpread(maxBorrowingSpread + 1);
    }

    // --- Getters ---

    // Returns collateral
    function testGetPositionCollateral() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory alicePosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 150 * MathUtils._100_PERCENT / 100
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.OpenPositionResult memory bobPosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 150 * MathUtils._100_PERCENT / 100
        });
        vm.stopPrank();

        assertEq(positionManager.raftCollateralToken().balanceOf(ALICE), alicePosition.collateral);
        assertEq(positionManager.raftCollateralToken().balanceOf(BOB), bobPosition.collateral);
    }

    // Returns debt
    function testGetPositionDebt() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory alicePosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 150 * MathUtils._100_PERCENT / 100
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.OpenPositionResult memory bobPosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 150 * MathUtils._100_PERCENT / 100
        });
        vm.stopPrank();

        assertEq(positionManager.raftDebtToken().balanceOf(ALICE), alicePosition.totalDebt);
        assertEq(positionManager.raftDebtToken().balanceOf(BOB), bobPosition.totalDebt);
    }
}
