// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { OneStepLeverageStETH } from "../contracts/OneStepLeverageStETH.sol";
import { PositionManager } from "../contracts/PositionManager.sol";
import { IAMM } from "../contracts/Interfaces/IAMM.sol";
import { IWstETHWrapper } from "../contracts/Interfaces/IWstETHWrapper.sol";
import { IPositionManager } from "../contracts/Interfaces/IPositionManager.sol";
import { IPositionManagerDependent } from "../contracts/Interfaces/IPositionManagerDependent.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";
import { MockAMM } from "./mocks/MockAMM.sol";
import { SplitLiquidationCollateral } from "../contracts/SplitLiquidationCollateral.sol";
import { PriceFeedTestnet } from "./mocks/PriceFeedTestnet.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { IWstETH } from "../contracts/Dependencies/IWstETH.sol";
import { IStETH } from "../contracts/Dependencies/IStETH.sol";
import { IERC20Indexable } from "../contracts/Interfaces/IERC20Indexable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OneStepLeverageStETHTest is TestSetup {
    using Fixed256x18 for uint256;

    IWstETH public constant wstETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    address public constant ETH_WHALE = 0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8;
    PriceFeedTestnet public priceFeed;
    OneStepLeverageStETH public oneStepLeverageStETH;
    IStETH public stETH;

    function setUp() public override {
        vm.createSelectFork("mainnet", 16_974_953);
        super.setUp();

        stETH = IStETH(address(wstETH.stETH()));
        priceFeed = new PriceFeedTestnet();
        positionManager.addCollateralToken(wstETH, priceFeed);

        IAMM mockAmm = new MockAMM(wstETH, positionManager.rToken(), 200e18);
        oneStepLeverageStETH = new OneStepLeverageStETH(positionManager, mockAmm, wstETH);
        // collateralToken.mint(address(oneStepLeverageStETH.amm()), 10e36);
        // collateralToken.mint(ALICE, 10e36);
        vm.startPrank(ETH_WHALE);
        address(stETH).call{ value: 10_000e18 }("");
        address(wstETH).call{ value: 10_000e18 }("");
        address(ALICE).call{ value: 10_000e18 }("");

        wstETH.transfer(address(oneStepLeverageStETH.amm()), 1000e18);
        wstETH.transfer(ALICE, 1000e18);
        stETH.transfer(ALICE, 1000e18);
        wstETH.transfer(BOB, 1000e18);
        stETH.transfer(BOB, 1000e18);
        vm.stopPrank();
        vm.startPrank(address(positionManager));
        positionManager.rToken().mint(address(this), 1_000_000_000e18);
        positionManager.rToken().mint(address(oneStepLeverageStETH.amm()), 10e36);
        vm.stopPrank();

        vm.prank(ALICE);
        positionManager.whitelistDelegate(address(oneStepLeverageStETH), true);

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: wstETH,
            position: BOB,
            icr: 2e18
        });
        vm.stopPrank();
    }

    function testOpenLeveragedPositionWithStETH() public {
        uint256 collateralAmount = 42e18;
        uint256 leverageMultiplier = 9e18;
        uint256 price = priceFeed.getPrice();
        uint256 targetDebt =
            stETH.getSharesByPooledEth(collateralAmount).mulDown(price).mulDown(leverageMultiplier - 1e18);
        uint256 minReturn =
            stETH.getSharesByPooledEth(collateralAmount).mulDown(leverageMultiplier - 1e18).mulDown(1e18 - 1e15);

        vm.startPrank(ALICE);
        stETH.approve(address(oneStepLeverageStETH), collateralAmount);
        oneStepLeverageStETH.manageLeveragedPositionStETH(
            targetDebt, true, collateralAmount, true, "", minReturn, MathUtils._100_PERCENT
        );

        checkEffectiveLeverage(ALICE, leverageMultiplier);
    }

    function testOpenLeveragedPositionWithETH() public {
        uint256 collateralAmount = 42e18;
        uint256 leverageMultiplier = 9e18;
        uint256 price = priceFeed.getPrice();
        uint256 targetDebt =
            stETH.getSharesByPooledEth(collateralAmount).mulDown(price).mulDown(leverageMultiplier - 1e18);
        uint256 minReturn =
            stETH.getSharesByPooledEth(collateralAmount).mulDown(leverageMultiplier - 1e18).mulDown(1e18 - 1e15);

        vm.startPrank(ALICE);
        oneStepLeverageStETH.manageLeveragedPositionETH{ value: collateralAmount }(
            targetDebt, true, "", minReturn, MathUtils._100_PERCENT
        );

        checkEffectiveLeverage(ALICE, leverageMultiplier);
    }

    function testManageLeveragedPositionETHWithNoValueFails() public {
        vm.expectRevert(IWstETHWrapper.SendingEtherFailed.selector);
        oneStepLeverageStETH.manageLeveragedPositionETH{ value: 0 }(1, true, "", 1, MathUtils._100_PERCENT);
    }

    function testReduceLeveragedPositionWithStETH() public {
        uint256 collateralAmount = 42e18;
        uint256 leverageMultiplier = 9e18;
        uint256 price = priceFeed.getPrice();
        uint256 targetDebt =
            stETH.getSharesByPooledEth(collateralAmount).mulDown(price).mulDown(leverageMultiplier - 1e18);
        uint256 minReturn =
            stETH.getSharesByPooledEth(collateralAmount).mulDown(leverageMultiplier - 1e18).mulDown(1e18 - 1e15);

        vm.startPrank(ALICE);
        stETH.approve(address(oneStepLeverageStETH), collateralAmount);
        oneStepLeverageStETH.manageLeveragedPositionStETH(
            targetDebt, true, collateralAmount, true, "", minReturn, MathUtils._100_PERCENT
        );

        uint256 stEthToWithdraw = 123_456_789;
        uint256 stEthBalanceBefore = stETH.balanceOf(ALICE);
        oneStepLeverageStETH.manageLeveragedPositionStETH(
            10_000, true, stEthToWithdraw, false, "", 0, MathUtils._100_PERCENT
        );

        assertApproxEqAbs(stETH.balanceOf(ALICE) - stEthBalanceBefore, stEthToWithdraw, 10);
    }

    function checkEffectiveLeverage(address position, uint256 targetLeverageMultiplier) internal {
        (IERC20Indexable raftCollateralToken,) = positionManager.raftCollateralTokens(wstETH);
        uint256 debtAfter = positionManager.raftDebtToken().balanceOf(position);
        uint256 collAfter = raftCollateralToken.balanceOf(position);
        (uint256 price,) = positionManager.priceFeeds(wstETH).fetchPrice();
        uint256 collAfterExpressedInR = price.mulDown(collAfter);
        uint256 effectiveLeverage = collAfterExpressedInR.divDown(collAfterExpressedInR - debtAfter);
        assertEq(effectiveLeverage, targetLeverageMultiplier);
    }
}
