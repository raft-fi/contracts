// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { IERC20Indexable } from "../contracts/Interfaces/IERC20Indexable.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { IPositionManager, PositionManager } from "../contracts/PositionManager.sol";
import { IERC20Wrapped, PositionManagerOngoingInterest } from "../contracts/PositionManagerOngoingInterest.sol";
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

        (IERC20Indexable raftCollateralToken, IERC20Indexable debtToken,,,,,,,,) =
            positionManager.collateralInfo(wrappedCollateralToken);

        uint256 positionCollateralBefore = raftCollateralToken.balanceOf(ALICE);
        assertEq(positionCollateralBefore, result.collateral);

        uint256 positionManagerWCTBalanceBefore = wrappedCollateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerWCTBalanceBefore, result.collateral);

        skip(365 days);
        uint256 debtBefore = debtToken.balanceOf(ALICE);
        uint256 collateralTopUpAmount = 0.01e18;
        vm.prank(ALICE);
        positionManagerOngoingInterest.managePosition(collateralTopUpAmount, true, 0, false, 0, emptySignature);

        /// debt should have increased by 10%
        assertApproxEqAbs(debtToken.balanceOf(ALICE), debtBefore * 1.1e18 / 1e18, 1e11);

        assertEq(raftCollateralToken.balanceOf(ALICE), positionCollateralBefore + collateralTopUpAmount);
        assertEq(
            wrappedCollateralToken.balanceOf(address(positionManager)),
            positionManagerWCTBalanceBefore + collateralTopUpAmount
        );
    }
}
