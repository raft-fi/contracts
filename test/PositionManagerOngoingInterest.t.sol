// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { IERC20Indexable } from "../contracts/Interfaces/IERC20Indexable.sol";
import { IRToken } from "../contracts/Interfaces/IRToken.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { IPositionManager, PositionManager } from "../contracts/PositionManager.sol";
import { IERC20Wrapped, PositionManagerOngoingInterest } from "../contracts/PositionManagerOngoingInterest.sol";
import { IPositionManagerWrappedCollateralToken } from
    "../contracts/Interfaces/IPositionManagerWrappedCollateralToken.sol";
import { SplitLiquidationCollateral } from "../contracts/SplitLiquidationCollateral.sol";
import { WrappedCollateralTokenLockable } from "../contracts/WrappedCollateralTokenLockable.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";
import { PriceFeedTestnet } from "./mocks/PriceFeedTestnet.sol";

contract PositionManagerOngoingInterestTest is TestSetup {
    using Fixed256x18 for uint256;

    PriceFeedTestnet public priceFeed;
    PositionManagerOngoingInterest public positionManagerOngoingInterest;
    WrappedCollateralTokenLockable public wrappedCollateralToken;

    uint256 public constant DEFAULT_PRICE = 200e18;
    // 10% APR
    uint256 public constant DEFAULT_INTEREST_RATE_PER_SECOND = 3_170_979_198;

    function setUp() public override {
        super.setUp();

        wrappedCollateralToken = new WrappedCollateralTokenLockable(
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

        positionManagerOngoingInterest = new PositionManagerOngoingInterest(
            address(positionManager),
            IERC20Wrapped(address(wrappedCollateralToken)),
            DEFAULT_INTEREST_RATE_PER_SECOND
        );

        wrappedCollateralToken.whitelistAddress(address(positionManagerOngoingInterest), true);

        vm.startPrank(ALICE);
        positionManager.whitelistDelegate(address(positionManagerOngoingInterest), true);
        collateralToken.approve(address(positionManagerOngoingInterest), type(uint256).max);
        vm.stopPrank();

        collateralToken.mint(ALICE, 10e36);

        priceFeed.setPrice(DEFAULT_PRICE);
    }

    // function testGetPosition() public {
    //     vm.startPrank(ALICE);
    //     PositionManagerUtils.OpenPositionResult memory alicePosition = PositionManagerUtils
    //         .openPositionWrappedCollateralToken({
    //         positionManagerWrappedCollToken: positionManagerOngoingInterest,
    //         priceFeed: priceFeed,
    //         icr: 150 * MathUtils._100_PERCENT / 100,
    //         extraDebt: 0
    //     });
    //     vm.stopPrank();

    //     (IERC20Indexable raftCollateralToken, IERC20Indexable raftDebtToken,,,,,,,,) =
    //         positionManager.collateralInfo(wrappedCollateralToken);
    //     uint256 alicePositionCollateral = raftCollateralToken.balanceOf(ALICE);
    //     uint256 aliceDebt = raftDebtToken.balanceOf(ALICE);

    //     assertEq(alicePositionCollateral, alicePosition.collateral);
    //     assertEq(aliceDebt, alicePosition.totalDebt);
    // }

    function testDeposit() public {
        uint256 rBalanceBefore = positionManager.rToken().balanceOf(ALICE);
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory result;
        result = PositionManagerUtils.openPositionWrappedCollateralToken({
            positionManagerWrappedCollToken: positionManagerOngoingInterest,
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
        positionManagerOngoingInterest.managePosition(collateralTopUpAmount, true, 0, false, 0, emptySignature);
        vm.stopPrank();

        uint256 positionCollateralAfter = raftCollateralToken.balanceOf(ALICE);
        assertEq(positionCollateralAfter, positionCollateralBefore + collateralTopUpAmount);

        uint256 positionManagerWCTBalanceAfter = wrappedCollateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerWCTBalanceAfter, positionManagerWCTBalanceBefore + collateralTopUpAmount);
    }

    // // Sends the correct amount of collateral to the user
    // function testWithdraw() public {
    //     vm.startPrank(ALICE);
    //     PositionManagerUtils.openPositionWrappedCollateralToken({
    //         positionManagerWrappedCollToken: positionManagerOngoingInterest,
    //         priceFeed: priceFeed,
    //         icr: 2 * MathUtils._100_PERCENT,
    //         extraDebt: 0
    //     });
    //     vm.stopPrank();

    //     uint256 aliceBalanceBefore = collateralToken.balanceOf(ALICE);
    //     uint256 withdrawAmount = 1 ether;

    //     vm.prank(ALICE);
    //     positionManagerOngoingInterest.managePosition(withdrawAmount, false, 0, false, 0, emptySignature);
    //     assertEq(collateralToken.balanceOf(ALICE), aliceBalanceBefore + withdrawAmount);
    // }

    // // Sends the correct amount to the user
    // function testWithdrawAlongWithRRepayment() public {
    //     vm.startPrank(ALICE);
    //     PositionManagerUtils.openPositionWrappedCollateralToken({
    //         positionManagerWrappedCollToken: positionManagerOngoingInterest,
    //         priceFeed: priceFeed,
    //         icr: 2 * MathUtils._100_PERCENT,
    //         extraDebt: 2 ether
    //     });
    //     vm.stopPrank();

    //     uint256 aliceBalanceBefore = collateralToken.balanceOf(ALICE);
    //     uint256 withdrawAmount = 1 ether;

    //     uint256 rBalanceBefore = positionManager.rToken().balanceOf(ALICE);

    //     vm.startPrank(ALICE);
    //     positionManager.rToken().approve(address(positionManagerOngoingInterest), 1 ether);
    //     positionManagerOngoingInterest.managePosition(withdrawAmount, false, 1 ether, false, 0, emptySignature);
    //     vm.stopPrank();

    //     assertEq(positionManager.rToken().balanceOf(ALICE), rBalanceBefore - 1 ether);
    //     assertEq(collateralToken.balanceOf(ALICE), aliceBalanceBefore + withdrawAmount);
    // }
}
