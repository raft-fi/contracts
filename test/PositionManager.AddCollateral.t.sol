// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IPositionManager } from "../contracts/Interfaces/IPositionManager.sol";
import { PositionManager } from "../contracts/PositionManager.sol";
import { SplitLiquidationCollateral } from "../contracts/SplitLiquidationCollateral.sol";
import { IERC20Indexable } from "../contracts/Interfaces/IERC20Indexable.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { PriceFeedTestnet } from "./TestContracts/PriceFeedTestnet.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";

contract PositionManagerAddCollateralTest is TestSetup {
    uint256 public constant DEFAULT_PRICE = 200e18;

    PriceFeedTestnet public priceFeed;
    IPositionManager public positionManager;

    function setUp() public override {
        super.setUp();

        priceFeed = new PriceFeedTestnet();
        splitLiquidationCollateral = new SplitLiquidationCollateral();
        positionManager = new PositionManager(
            splitLiquidationCollateral
        );
        positionManager.addCollateralToken(collateralToken, priceFeed);

        collateralToken.mint(ALICE, 10e36);
        collateralToken.mint(BOB, 10e36);
        collateralToken.mint(CAROL, 10e36);
    }

    // reverts when top-up would leave position with ICR < MCR
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

        assertLt(PositionManagerUtils.getCurrentICR(positionManager, collateralToken, ALICE, price), MathUtils.MCR);

        uint256 collateralTopUpAmount = 1;

        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), collateralTopUpAmount);
        vm.expectRevert(abi.encodeWithSelector(IPositionManager.NewICRLowerThanMCR.selector, MathUtils._100_PERCENT));
        positionManager.managePosition(collateralToken, collateralTopUpAmount, true, 0, false, 0);
        vm.stopPrank();
    }

    // Increases the position manager's collateral token balance by correct amount
    function testPositionManagerBalanceIncrease() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory result = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 positionManagerBalanceBefore = collateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerBalanceBefore, result.collateral);

        uint256 collateralTopUpAmount = 1 ether;

        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), collateralTopUpAmount);
        positionManager.managePosition(collateralToken, collateralTopUpAmount, true, 0, false, 0);
        vm.stopPrank();

        uint256 positionManagerBalanceAfter = collateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerBalanceAfter, positionManagerBalanceBefore + collateralTopUpAmount);
    }

    // Active position: adds the correct collateral amount to the position
    function testPositionCollateralIncrease() public {
        // Alice creates a position and adds first collateral
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            icr: 2e18
        });
        vm.stopPrank();

        (IERC20Indexable raftCollateralToken,) = positionManager.raftCollateralTokens(collateralToken);
        uint256 positionCollateralBefore = raftCollateralToken.balanceOf(ALICE);
        uint256 collateralTopUpAmount = 1 ether;

        // Alice adds second collateral
        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), collateralTopUpAmount);
        positionManager.managePosition(collateralToken, collateralTopUpAmount, true, 0, false, 0);
        vm.stopPrank();

        uint256 positionCollateralAfter = raftCollateralToken.balanceOf(ALICE);
        assertEq(positionCollateralAfter, positionCollateralBefore + collateralTopUpAmount);
    }

    // Reverts if position is non-existent or closed
    function testInvalidPosition() public {
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

        // Carol attempts to add collateral to her non-existent position
        vm.startPrank(CAROL);
        collateralToken.approve(address(positionManager), 1 ether);
        vm.expectRevert(IPositionManager.InvalidPosition.selector);
        positionManager.managePosition(collateralToken, 1 ether, true, 0, false, 0);
        vm.stopPrank();

        // Price drops
        priceFeed.setPrice(100e18);

        // Bob gets liquidated
        positionManager.liquidate(collateralToken, BOB);

        assertEq(address(positionManager.collateralTokenForPosition(BOB)), address(0));
        assertEq(positionManager.raftDebtToken().balanceOf(BOB), 0);

        // Bob attempts to add collateral to his closed position
        vm.startPrank(BOB);
        collateralToken.approve(address(positionManager), 1 ether);
        vm.expectRevert(IPositionManager.InvalidPosition.selector);
        positionManager.managePosition(collateralToken, 1 ether, true, 0, false, 0);
        vm.stopPrank();
    }
}
