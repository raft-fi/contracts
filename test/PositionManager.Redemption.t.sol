// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { PositionManager } from "../contracts/PositionManager.sol";
import { IERC20Indexable } from "../contracts/Interfaces/IERC20Indexable.sol";
import { IRToken } from "../contracts/Interfaces/IRToken.sol";
import { PriceFeedTestnet } from "./TestContracts/PriceFeedTestnet.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";

contract PositionManagerRedemptionTest is TestSetup {
    using Fixed256x18 for uint256;

    uint256 public constant DEFAULT_PRICE = 200e18;

    PriceFeedTestnet public priceFeed;
    PositionManager public positionManager;
    IRToken public rToken;

    function setUp() public override {
        super.setUp();

        priceFeed = new PriceFeedTestnet();
        positionManager = new PositionManager(splitLiquidationCollateral);
        rToken = positionManager.rToken();

        positionManager.addCollateralToken(collateralToken, priceFeed);

        collateralToken.mint(ALICE, 10e36);
        collateralToken.mint(BOB, 10e36);
        collateralToken.mint(CAROL, 10e36);
        collateralToken.mint(DAVE, 10e36);
        collateralToken.mint(EVE, 10e36);
        collateralToken.mint(FRANK, 10e36);

        priceFeed.setPrice(DEFAULT_PRICE);
    }

    function testRedeemCollateralWhenOnlyOnePositionActive() public {
        uint256 initialCR = 1.5e18;
        uint256 rToMint = 400_000e18;
        uint256 rToRedeem = 100_000e18;
        uint256 collateralAmount = rToMint.divUp(DEFAULT_PRICE).mulUp(initialCR);

        (IERC20Indexable raftCollateralToken,) = positionManager.raftCollateralTokens(collateralToken);

        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), collateralAmount);
        positionManager.managePosition(
            collateralToken,
            collateralAmount,
            true, // collateral increase
            rToMint,
            true, // debt increase
            1e17
        );
        rToken.transfer(BOB, rToRedeem);
        vm.stopPrank();

        assertEq(positionManager.raftDebtToken().balanceOf(ALICE), rToMint);
        assertEq(collateralToken.balanceOf(address(positionManager)), collateralAmount);
        assertEq(raftCollateralToken.balanceOf(ALICE), collateralAmount);

        uint256 bobCollateralTokenBalanceBefore = collateralToken.balanceOf(BOB);
        uint256 feeRecipientBalanceBefore = collateralToken.balanceOf(address(positionManager.feeRecipient()));
        uint256 collateralToRemoveFromPool = rToRedeem.divDown(DEFAULT_PRICE);
        uint256 collateralToRedeem = 432.5e18;
        uint256 collateralFee = collateralToRemoveFromPool - collateralToRedeem;

        vm.startPrank(BOB);
        positionManager.redeemCollateral(collateralToken, rToRedeem, 1e18);
        vm.stopPrank();

        uint256 redeemedAmount = collateralToken.balanceOf(BOB) - bobCollateralTokenBalanceBefore;
        assertEq(redeemedAmount, collateralToRedeem);
        uint256 feeRecipientBalanceAfter = collateralToken.balanceOf(address(positionManager.feeRecipient()));
        assertEq(feeRecipientBalanceAfter - feeRecipientBalanceBefore, collateralFee);
        assertEq(collateralToken.balanceOf(address(positionManager)), collateralAmount - collateralToRemoveFromPool);
        assertApproxEqAbs(raftCollateralToken.balanceOf(ALICE), collateralAmount - collateralToRemoveFromPool, 1e5);
        assertEq(positionManager.raftDebtToken().balanceOf(ALICE), rToMint - rToRedeem);
    }
}
