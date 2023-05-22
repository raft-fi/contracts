// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { PositionManager } from "../contracts/PositionManager.sol";
import { IERC20Indexable } from "../contracts/Interfaces/IERC20Indexable.sol";
import { IRToken } from "../contracts/Interfaces/IRToken.sol";
import { IPositionManager } from "../contracts/Interfaces/IPositionManager.sol";
import { PriceFeedTestnet } from "./mocks/PriceFeedTestnet.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";

contract PositionManagerRedemptionTest is TestSetup {
    using Fixed256x18 for uint256;

    uint256 public constant DEFAULT_PRICE = 200e18;

    PriceFeedTestnet public priceFeed;
    IRToken public rToken;

    function setUp() public override {
        super.setUp();

        priceFeed = new PriceFeedTestnet();
        rToken = positionManager.rToken();

        positionManager.addCollateralToken(collateralToken, priceFeed, splitLiquidationCollateral);
        positionManager.setRedemptionSpread(collateralToken, MathUtils._100_PERCENT / 100); // 1%
        positionManager.setRedemptionRebate(collateralToken, MathUtils._100_PERCENT / 2); // 50%

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

        (IERC20Indexable raftCollateralToken, IERC20Indexable raftDebtToken,,,,,,,,) =
            positionManager.collateralInfo(collateralToken);

        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), collateralAmount);
        positionManager.managePosition(
            collateralToken,
            ALICE,
            collateralAmount,
            true, // collateral increase
            rToMint,
            true, // debt increase
            1e17,
            emptySignature
        );
        rToken.transfer(BOB, rToRedeem);
        vm.stopPrank();

        assertEq(raftDebtToken.balanceOf(ALICE), rToMint);
        assertEq(collateralToken.balanceOf(address(positionManager)), collateralAmount);
        assertEq(raftCollateralToken.balanceOf(ALICE), collateralAmount);

        uint256 bobCollateralTokenBalanceBefore = collateralToken.balanceOf(BOB);
        uint256 feeRecipientBalanceBefore = collateralToken.balanceOf(address(positionManager.feeRecipient()));
        uint256 matchingCollateral = rToRedeem.divDown(DEFAULT_PRICE);
        uint256 collateralToRedeem = 430e18;
        uint256 collateralFee = matchingCollateral - collateralToRedeem;
        uint256 rebate = collateralFee.mulDown(positionManager.redemptionRebate(collateralToken));
        uint256 collateralToRemoveFromPool = matchingCollateral - rebate;

        vm.startPrank(BOB);
        positionManager.redeemCollateral(collateralToken, rToRedeem, 1e18);
        vm.stopPrank();

        uint256 redeemedAmount = collateralToken.balanceOf(BOB) - bobCollateralTokenBalanceBefore;
        assertEq(redeemedAmount, collateralToRedeem);
        uint256 feeRecipientBalanceAfter = collateralToken.balanceOf(address(positionManager.feeRecipient()));
        assertEq(feeRecipientBalanceAfter - feeRecipientBalanceBefore, collateralFee - rebate);
        assertEq(collateralToken.balanceOf(address(positionManager)), collateralAmount - collateralToRemoveFromPool);
        assertApproxEqAbs(raftCollateralToken.balanceOf(ALICE), collateralAmount - collateralToRemoveFromPool, 1e5);
        assertEq(raftDebtToken.balanceOf(ALICE), rToMint - rToRedeem);
    }

    function testRedeemBelowThreshold() public {
        uint256 initialCR = 1.5e18;
        uint256 rToMint = 400_000e18;
        uint256 collateralAmount = rToMint.divUp(DEFAULT_PRICE).mulUp(initialCR);
        uint256 rToRedeem = 397_001e18;

        (IERC20Indexable raftCollateralToken, IERC20Indexable raftDebtToken,,,,,,,,) =
            positionManager.collateralInfo(collateralToken);

        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), collateralAmount);
        positionManager.managePosition(
            collateralToken,
            ALICE,
            collateralAmount,
            true, // collateral increase
            rToMint,
            true, // debt increase
            1e17,
            emptySignature
        );
        rToken.transfer(BOB, rToRedeem);
        vm.stopPrank();

        assertEq(raftDebtToken.balanceOf(ALICE), rToMint);
        assertEq(collateralToken.balanceOf(address(positionManager)), collateralAmount);
        assertEq(raftCollateralToken.balanceOf(ALICE), collateralAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPositionManager.TotalDebtCannotBeLowerThanMinDebt.selector, collateralToken, 2999e18
            )
        );
        vm.startPrank(BOB);
        positionManager.redeemCollateral(collateralToken, rToRedeem, 1e18);
        vm.stopPrank();
    }

    function testRedeemCollateralWhenMultipleActivePositions() public {
        uint256 rToRedeem = 100_000e18;

        (IERC20Indexable raftCollateralToken, IERC20Indexable raftDebtToken,,,,,,,,) =
            positionManager.collateralInfo(collateralToken);

        uint256 initialCR_A = 1.5e18;
        uint256 rToMint_A = 400_000e18;
        uint256 collateralAmount_A = rToMint_A.divUp(DEFAULT_PRICE).mulUp(initialCR_A);
        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), collateralAmount_A);
        positionManager.managePosition(
            collateralToken,
            ALICE,
            collateralAmount_A,
            true, // collateral increase
            rToMint_A,
            true, // debt increase
            1e17,
            emptySignature
        );
        rToken.transfer(BOB, rToRedeem);
        vm.stopPrank();

        uint256 initialCR_C = 1.7e18;
        uint256 rToMint_C = 123_000e18;
        uint256 collateralAmount_C = rToMint_C.divUp(DEFAULT_PRICE).mulUp(initialCR_C);
        vm.startPrank(CAROL);
        collateralToken.approve(address(positionManager), collateralAmount_C);
        positionManager.managePosition(
            collateralToken,
            CAROL,
            collateralAmount_C,
            true, // collateral increase
            rToMint_C,
            true, // debt increase
            1e17,
            emptySignature
        );
        vm.stopPrank();

        uint256 bobCollateralTokenBalanceBefore = collateralToken.balanceOf(BOB);
        uint256 feeRecipientBalanceBefore = collateralToken.balanceOf(address(positionManager.feeRecipient()));
        uint256 matchingCollateral = rToRedeem.divDown(DEFAULT_PRICE);
        uint256 collateralToRedeem = 444_698_852_772_466_539_500;
        uint256 collateralFee = matchingCollateral - collateralToRedeem;
        uint256 rebate = collateralFee.mulDown(positionManager.redemptionRebate(collateralToken));
        uint256 collateralToRemoveFromPool = matchingCollateral - rebate;

        vm.startPrank(BOB);
        positionManager.redeemCollateral(collateralToken, rToRedeem, 1e18);
        vm.stopPrank();

        uint256 redeemedAmount = collateralToken.balanceOf(BOB) - bobCollateralTokenBalanceBefore;
        assertEq(redeemedAmount, collateralToRedeem);
        uint256 feeRecipientBalanceAfter = collateralToken.balanceOf(address(positionManager.feeRecipient()));

        assertEq(feeRecipientBalanceAfter - feeRecipientBalanceBefore, collateralFee - rebate);

        assertEq(
            collateralToken.balanceOf(address(positionManager)),
            collateralAmount_A + collateralAmount_C - collateralToRemoveFromPool
        );

        assertApproxEqAbs(
            raftCollateralToken.balanceOf(ALICE),
            collateralAmount_A
                - collateralToRemoveFromPool * collateralAmount_A / (collateralAmount_A + collateralAmount_C),
            1e5
        );
        assertApproxEqAbs(
            raftDebtToken.balanceOf(ALICE), rToMint_A - rToRedeem * rToMint_A / (rToMint_A + rToMint_C), 1e5
        );

        assertApproxEqAbs(
            raftCollateralToken.balanceOf(CAROL),
            collateralAmount_C
                - collateralToRemoveFromPool * collateralAmount_C / (collateralAmount_A + collateralAmount_C),
            1e5
        );
        assertApproxEqAbs(
            raftDebtToken.balanceOf(CAROL), rToMint_C - rToRedeem * rToMint_C / (rToMint_A + rToMint_C), 1e5
        );
    }
}
