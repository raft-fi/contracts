// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { IERC20Indexable } from "../contracts/Interfaces/IERC20Indexable.sol";
import { IRToken } from "../contracts/Interfaces/IRToken.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { IPositionManager, PositionManager } from "../contracts/PositionManager.sol";
import {
    IERC20Wrapped,
    IPositionManagerWrappedCollateralToken,
    PositionManagerWrappedCollateralToken
} from "../contracts/PositionManagerWrappedCollateralToken.sol";
import { SplitLiquidationCollateral } from "../contracts/SplitLiquidationCollateral.sol";
import { WrappedCollateralToken } from "../contracts/WrappedCollateralToken.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";
import { PriceFeedTestnet } from "./mocks/PriceFeedTestnet.sol";

contract PositionManagerWrappedCollateralTokenTest is TestSetup {
    using Fixed256x18 for uint256;

    PriceFeedTestnet public priceFeed;
    PositionManagerWrappedCollateralToken public positionManagerWrappedCollToken;
    WrappedCollateralToken public wrappedCollateralToken;

    uint256 public constant DEFAULT_PRICE = 200e18;

    function setUp() public override {
        super.setUp();

        wrappedCollateralToken = new WrappedCollateralToken(
            collateralToken, 
            "Wrapped Collateral Token", 
            "WCT", 
            100_000_0e18,
            type(uint256).max, 
            address(positionManager)
        );
        priceFeed = new PriceFeedTestnet();
        positionManager.addCollateralToken(wrappedCollateralToken, priceFeed, splitLiquidationCollateral);
        positionManager.setRedemptionSpread(wrappedCollateralToken, MathUtils._100_PERCENT / 100); // 1%
        positionManager.setRedemptionRebate(wrappedCollateralToken, MathUtils._100_PERCENT / 2); // 50%

        positionManagerWrappedCollToken = new PositionManagerWrappedCollateralToken(
            address(positionManager),
            IERC20Wrapped(address(wrappedCollateralToken))
        );

        vm.startPrank(ALICE);
        positionManager.whitelistDelegate(address(positionManagerWrappedCollToken), true);
        collateralToken.approve(address(positionManagerWrappedCollToken), type(uint256).max);
        vm.stopPrank();

        collateralToken.mint(ALICE, 10e36);

        priceFeed.setPrice(DEFAULT_PRICE);
    }

    function testCannotCreatePositionManagerWrappedCollateralToken() public {
        vm.expectRevert(IPositionManagerWrappedCollateralToken.WrappedCollateralTokenAddressCannotBeZero.selector);
        new PositionManagerWrappedCollateralToken(
            address(positionManager),
            IERC20Wrapped(address(0))
        );
    }

    function testGetPosition() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory alicePosition = PositionManagerUtils
            .openPositionWrappedCollateralToken({
            positionManagerWrappedCollToken: positionManagerWrappedCollToken,
            priceFeed: priceFeed,
            icr: 150 * MathUtils._100_PERCENT / 100,
            extraDebt: 0
        });
        vm.stopPrank();

        (IERC20Indexable raftCollateralToken, IERC20Indexable raftDebtToken,,,,,,,,) =
            positionManager.collateralInfo(wrappedCollateralToken);
        uint256 alicePositionCollateral = raftCollateralToken.balanceOf(ALICE);
        uint256 aliceDebt = raftDebtToken.balanceOf(ALICE);

        assertEq(alicePositionCollateral, alicePosition.collateral);
        assertEq(aliceDebt, alicePosition.totalDebt);
    }

    function testDeposit() public {
        uint256 rBalanceBefore = positionManager.rToken().balanceOf(ALICE);
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory result;
        result = PositionManagerUtils.openPositionWrappedCollateralToken({
            positionManagerWrappedCollToken: positionManagerWrappedCollToken,
            priceFeed: priceFeed,
            icr: 2 * MathUtils._100_PERCENT,
            extraDebt: 0
        });
        vm.stopPrank();
        assertGt(positionManager.rToken().balanceOf(ALICE), rBalanceBefore);

        (IERC20Indexable raftCollateralToken,,,,,,,,,) = positionManager.collateralInfo(wrappedCollateralToken);

        uint256 positionCollateralBefore = raftCollateralToken.balanceOf(ALICE);
        assertEq(positionCollateralBefore, result.collateral);

        uint256 positionManagerWCTBalanceBefore = wrappedCollateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerWCTBalanceBefore, result.collateral);

        uint256 collateralTopUpAmount = 1 ether;

        vm.startPrank(ALICE);
        positionManagerWrappedCollToken.managePosition(collateralTopUpAmount, true, 0, false, 0, emptySignature);
        vm.stopPrank();

        uint256 positionCollateralAfter = raftCollateralToken.balanceOf(ALICE);
        assertEq(positionCollateralAfter, positionCollateralBefore + collateralTopUpAmount);

        uint256 positionManagerWCTBalanceAfter = wrappedCollateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerWCTBalanceAfter, positionManagerWCTBalanceBefore + collateralTopUpAmount);
    }

    function testCannotDeposit() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPositionWrappedCollateralToken({
            positionManagerWrappedCollToken: positionManagerWrappedCollToken,
            priceFeed: priceFeed,
            icr: 2 * MathUtils._100_PERCENT,
            extraDebt: 0
        });
        vm.stopPrank();

        vm.startPrank(ALICE);
        vm.expectRevert(IPositionManager.NoCollateralOrDebtChange.selector);
        positionManagerWrappedCollToken.managePosition(0, true, 0, false, 0, emptySignature);
        vm.stopPrank();

        vm.startPrank(ALICE);
        vm.expectRevert(IPositionManager.NoCollateralOrDebtChange.selector);
        positionManagerWrappedCollToken.managePosition(0, false, 0, false, 0, emptySignature);
        vm.stopPrank();
    }

    // Sends the correct amount of collateral to the user
    function testWithdraw() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPositionWrappedCollateralToken({
            positionManagerWrappedCollToken: positionManagerWrappedCollToken,
            priceFeed: priceFeed,
            icr: 2 * MathUtils._100_PERCENT,
            extraDebt: 0
        });
        vm.stopPrank();

        uint256 aliceBalanceBefore = collateralToken.balanceOf(ALICE);
        uint256 withdrawAmount = 1 ether;

        vm.prank(ALICE);
        positionManagerWrappedCollToken.managePosition(withdrawAmount, false, 0, false, 0, emptySignature);
        assertEq(collateralToken.balanceOf(ALICE), aliceBalanceBefore + withdrawAmount);
    }

    function testWithdrawAsMaxDebt() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPositionWrappedCollateralToken({
            positionManagerWrappedCollToken: positionManagerWrappedCollToken,
            priceFeed: priceFeed,
            icr: 2 * MathUtils._100_PERCENT,
            extraDebt: 0
        });
        vm.stopPrank();

        uint256 aliceBalanceBefore = collateralToken.balanceOf(ALICE);
        uint256 withdrawAmount = 30 ether;

        // Alice withdraws max debt
        vm.startPrank(ALICE);
        positionManager.rToken().approve(address(positionManagerWrappedCollToken), type(uint256).max);
        positionManagerWrappedCollToken.managePosition(0, false, type(uint256).max, false, 0, emptySignature);
        vm.stopPrank();
        assertEq(collateralToken.balanceOf(ALICE), aliceBalanceBefore + withdrawAmount);
    }

    // Sends the correct amount to the user
    function testWithdrawAlongWithRRepayment() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPositionWrappedCollateralToken({
            positionManagerWrappedCollToken: positionManagerWrappedCollToken,
            priceFeed: priceFeed,
            icr: 2 * MathUtils._100_PERCENT,
            extraDebt: 2 ether
        });
        vm.stopPrank();

        uint256 aliceBalanceBefore = collateralToken.balanceOf(ALICE);
        uint256 withdrawAmount = 1 ether;

        uint256 rBalanceBefore = positionManager.rToken().balanceOf(ALICE);

        vm.startPrank(ALICE);
        positionManager.rToken().approve(address(positionManagerWrappedCollToken), 1 ether);
        positionManagerWrappedCollToken.managePosition(withdrawAmount, false, 1 ether, false, 0, emptySignature);
        vm.stopPrank();

        assertEq(positionManager.rToken().balanceOf(ALICE), rBalanceBefore - 1 ether);
        assertEq(collateralToken.balanceOf(ALICE), aliceBalanceBefore + withdrawAmount);
    }

    function testRedeemCollateral() public {
        uint256 initialCR = 1.5e18;
        uint256 rToMint = 400_000e18;
        uint256 rToRedeem = 100_000e18;
        uint256 collateralAmount = rToMint.divUp(DEFAULT_PRICE).mulUp(initialCR);

        (IERC20Indexable raftCollateralToken, IERC20Indexable raftDebtToken,,,,,,,,) =
            positionManager.collateralInfo(wrappedCollateralToken);
        IRToken rToken = positionManager.rToken();

        vm.startPrank(ALICE);
        positionManagerWrappedCollToken.managePosition(
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
        assertEq(wrappedCollateralToken.balanceOf(address(positionManager)), collateralAmount);
        assertEq(raftCollateralToken.balanceOf(ALICE), collateralAmount);

        uint256 bobCollateralTokenBalanceBefore = collateralToken.balanceOf(BOB);
        uint256 feeRecipientBalanceBefore = wrappedCollateralToken.balanceOf(address(positionManager.feeRecipient()));
        uint256 matchingCollateral = rToRedeem.divDown(DEFAULT_PRICE);
        uint256 collateralToRedeem = 430e18;
        uint256 collateralFee = matchingCollateral - collateralToRedeem;
        uint256 rebate = collateralFee.mulDown(positionManager.redemptionRebate(wrappedCollateralToken));
        uint256 collateralToRemoveFromPool = matchingCollateral - rebate;

        vm.startPrank(BOB);
        rToken.approve(address(positionManagerWrappedCollToken), type(uint256).max);
        positionManagerWrappedCollToken.redeemCollateral(rToRedeem, 1e18, emptySignature);
        vm.stopPrank();

        uint256 redeemedAmount = collateralToken.balanceOf(BOB) - bobCollateralTokenBalanceBefore;
        assertEq(redeemedAmount, collateralToRedeem);
        uint256 feeRecipientBalanceAfter = wrappedCollateralToken.balanceOf(address(positionManager.feeRecipient()));
        assertEq(feeRecipientBalanceAfter - feeRecipientBalanceBefore, collateralFee - rebate);
        assertEq(
            wrappedCollateralToken.balanceOf(address(positionManager)), collateralAmount - collateralToRemoveFromPool
        );
        assertApproxEqAbs(raftCollateralToken.balanceOf(ALICE), collateralAmount - collateralToRemoveFromPool, 1e5);
        assertEq(raftDebtToken.balanceOf(ALICE), rToMint - rToRedeem);
    }
}
