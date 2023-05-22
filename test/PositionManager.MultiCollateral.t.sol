// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { IERC20Indexable } from "../contracts/Interfaces/IERC20Indexable.sol";
import { IPositionManager } from "../contracts/Interfaces/IPositionManager.sol";
import { IPriceFeed } from "../contracts/Interfaces/IPriceFeed.sol";
import { PositionManager } from "../contracts/PositionManager.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { PriceFeedTestnet } from "./mocks/PriceFeedTestnet.sol";
import { TokenMock } from "./mocks/TokenMock.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";

contract PositionManagerMultiCollateralTest is TestSetup {
    // --- Types ---

    using Fixed256x18 for uint256;

    uint256 public constant DEFAULT_PRICE = 200e18;

    PriceFeedTestnet public priceFeed;

    TokenMock public collateralTokenSecond;
    PriceFeedTestnet public priceFeedSecond;

    IERC20Indexable public raftDebtToken1;
    IERC20Indexable public raftDebtToken2;

    address public randomAddress;

    function setUp() public override {
        super.setUp();

        priceFeed = new PriceFeedTestnet();
        positionManager.addCollateralToken(collateralToken, priceFeed, splitLiquidationCollateral);

        collateralTokenSecond = new TokenMock();
        priceFeedSecond = new PriceFeedTestnet();
        positionManager.addCollateralToken(collateralTokenSecond, priceFeedSecond, splitLiquidationCollateral);

        (, raftDebtToken2,,,,,,,,) = positionManager.collateralInfo(collateralTokenSecond);
        (, raftDebtToken1,,,,,,,,) = positionManager.collateralInfo(collateralToken);

        randomAddress = makeAddr("randomAddress");

        collateralToken.mint(ALICE, 10e36);
        collateralToken.mint(BOB, 10e36);
        collateralToken.mint(CAROL, 10e36);
    }

    function testAddCollateralToken() public {
        TokenMock collateralTokenThird = new TokenMock();
        PriceFeedTestnet priceFeedThird = new PriceFeedTestnet();

        (IERC20Indexable raftCollateralThird, IERC20Indexable raftDebtThird,,, bool raftCollateralThirdEnabled,,,,,) =
            positionManager.collateralInfo(collateralTokenThird);
        assertEq(address(raftCollateralThird), address(0));
        assertFalse(raftCollateralThirdEnabled);

        positionManager.addCollateralToken(collateralTokenThird, priceFeedThird, splitLiquidationCollateral);

        (raftCollateralThird, raftDebtThird,,, raftCollateralThirdEnabled,,,,,) =
            positionManager.collateralInfo(collateralTokenThird);
        assertTrue(raftCollateralThird != IERC20(address(0)));
        assertTrue(raftCollateralThirdEnabled);
    }

    function testCannotAddCollateralToken() public {
        vm.expectRevert(IPositionManager.CollateralTokenAddressCannotBeZero.selector);
        positionManager.addCollateralToken(IERC20(address(0)), priceFeedSecond, splitLiquidationCollateral);

        vm.expectRevert(IPositionManager.PriceFeedAddressCannotBeZero.selector);
        positionManager.addCollateralToken(collateralTokenSecond, IPriceFeed(address(0)), splitLiquidationCollateral);

        vm.expectRevert(IPositionManager.CollateralTokenAlreadyAdded.selector);
        positionManager.addCollateralToken(collateralTokenSecond, priceFeedSecond, splitLiquidationCollateral);

        TokenMock collateralTokenThird = new TokenMock();
        PriceFeedTestnet priceFeedThird = new PriceFeedTestnet();
        vm.prank(randomAddress);
        vm.expectRevert("Ownable: caller is not the owner");
        positionManager.addCollateralToken(collateralTokenThird, priceFeedThird, splitLiquidationCollateral);
    }

    function testDepositTwoDifferentCollateralsWtihTwoDifferentUsers() public {
        // Alice add collateral with first collateral token
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory resultAlice = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 positionManagerBalanceBeforeAlice = collateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerBalanceBeforeAlice, resultAlice.collateral);

        uint256 collateralTopUpAmount = 1 ether;

        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), collateralTopUpAmount);
        positionManager.managePosition(
            collateralToken, ALICE, collateralTopUpAmount, true, 0, false, 0, emptySignature
        );
        vm.stopPrank();

        uint256 positionManagerBalanceAfterAlice = collateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerBalanceAfterAlice, positionManagerBalanceBeforeAlice + collateralTopUpAmount);

        // Bob add collateral with second collateral token
        collateralTokenSecond.mint(BOB, 10e36);

        vm.startPrank(BOB);
        PositionManagerUtils.OpenPositionResult memory resultBob = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeedSecond,
            collateralToken: collateralTokenSecond,
            position: BOB,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 positionManagerBalanceBeforeBob = collateralTokenSecond.balanceOf(address(positionManager));
        assertEq(positionManagerBalanceBeforeBob, resultBob.collateral);

        vm.startPrank(BOB);
        collateralTokenSecond.approve(address(positionManager), collateralTopUpAmount);
        positionManager.managePosition(
            collateralTokenSecond, BOB, collateralTopUpAmount, true, 0, false, 0, emptySignature
        );
        vm.stopPrank();

        uint256 positionManagerBalanceAfterBob = collateralTokenSecond.balanceOf(address(positionManager));
        assertEq(positionManagerBalanceAfterBob, positionManagerBalanceBeforeBob + collateralTopUpAmount);
    }

    function testDepositTwoDifferentCollateralsWtihSameUserAfterClosePositionWithFirst() public {
        // Alice add collateral with first collateral token
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory resultAlice = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 positionManagerBalanceBeforeAlice = collateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerBalanceBeforeAlice, resultAlice.collateral);

        // Alice close position with first collateral token
        vm.startPrank(ALICE);
        positionManager.managePosition(
            collateralToken, ALICE, 0, false, resultAlice.debtAmount, false, 0, emptySignature
        );
        vm.stopPrank();

        // Alice add collateral with second collateral token
        collateralTokenSecond.mint(ALICE, 10e36);
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory resultAliceSecondCollateral = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeedSecond,
            collateralToken: collateralTokenSecond,
            position: ALICE,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 positionManagerBalanceBeforeAliceSecondCollateral =
            collateralTokenSecond.balanceOf(address(positionManager));
        assertEq(positionManagerBalanceBeforeAliceSecondCollateral, resultAliceSecondCollateral.collateral);
    }

    function testCannotDepositTwoDifferentCollateralsWtihSameUser() public {
        // Alice add collateral with first collateral token
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory resultAlice = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 positionManagerBalanceBeforeAlice = collateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerBalanceBeforeAlice, resultAlice.collateral);

        uint256 collateralTopUpAmount = 1 ether;

        vm.startPrank(ALICE);
        collateralToken.approve(address(positionManager), collateralTopUpAmount);
        positionManager.managePosition(
            collateralToken, ALICE, collateralTopUpAmount, true, 0, false, 0, emptySignature
        );
        vm.stopPrank();

        uint256 positionManagerBalanceAfterAlice = collateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerBalanceAfterAlice, positionManagerBalanceBeforeAlice + collateralTopUpAmount);

        // Allice trying to add collateral with second collateral token
        collateralTokenSecond.mint(ALICE, 10e36);
        vm.startPrank(ALICE);
        vm.expectRevert(IPositionManager.PositionCollateralTokenMismatch.selector);
        positionManager.managePosition(
            collateralTokenSecond, ALICE, collateralTopUpAmount, true, 0, false, 0, emptySignature
        );
        vm.stopPrank();
    }

    function testLiquidation() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 20e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: BOB,
            icr: 4e18
        });
        vm.stopPrank();

        collateralTokenSecond.mint(CAROL, 10e36);
        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeedSecond,
            collateralToken: collateralTokenSecond,
            position: CAROL,
            icr: 2e18
        });
        vm.stopPrank();

        collateralTokenSecond.mint(DAVE, 10e36);
        vm.startPrank(DAVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeedSecond,
            collateralToken: collateralTokenSecond,
            position: DAVE,
            icr: 2e18
        });
        vm.stopPrank();

        uint256 price = priceFeed.getPrice();

        uint256 icrBefore = PositionManagerUtils.getCurrentICR(positionManager, collateralToken, BOB, price);
        assertEq(icrBefore, 4e18);

        // Bob increases debt to 180 R, lowering his ICR to 1.11
        uint256 targetICR = 1_111_111_111_111_111_111;
        vm.startPrank(BOB);
        PositionManagerUtils.withdrawDebt({
            positionManager: positionManager,
            collateralToken: collateralToken,
            priceFeed: priceFeed,
            position: BOB,
            icr: targetICR
        });
        vm.stopPrank();

        uint256 icrAfter = PositionManagerUtils.getCurrentICR(positionManager, collateralToken, BOB, price);
        assertEq(icrAfter, targetICR);

        // price drops to 1ETH:100R, reducing Bob's ICR below MCR
        priceFeed.setPrice(100e18);

        // liquidate Bob's position
        positionManager.liquidate(BOB);

        priceFeedSecond.setPrice(100e18);

        // Bob's position is closed
        assertEq(raftDebtToken1.balanceOf(BOB), 0);
        assertEq(raftDebtToken2.balanceOf(BOB), 0);
        /*assertEq(
            positionManager.raftDebtToken().balanceOf(CAROL),
            resultCarol.debtAmount.mulDown(positionManager.raftDebtToken().currentIndex())
        );*/

        // liquidate Carol's position
        positionManager.liquidate(CAROL);

        // Carol's position is closed
        assertEq(raftDebtToken1.balanceOf(CAROL), 0);
        assertEq(raftDebtToken2.balanceOf(CAROL), 0);

        // Check that position is correclty closed and open with new collateral token
        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: CAROL,
            icr: 2e18
        });
        vm.stopPrank();
    }

    function testDisabledCollateralToken() public {
        (,,,, bool raftCollateralTokenFirstEnabled,,,,,) = positionManager.collateralInfo(collateralToken);
        assertTrue(raftCollateralTokenFirstEnabled);

        (,,,, bool raftCollateralTokenSecondEnabled,,,,,) = positionManager.collateralInfo(collateralTokenSecond);
        assertTrue(raftCollateralTokenSecondEnabled);

        collateralTokenSecond.mint(BOB, 10e36);
        collateralTokenSecond.mint(CAROL, 10e36);

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
            collateralToken: collateralTokenSecond,
            position: BOB,
            extraDebtAmount: 1e18,
            icr: 2e18
        });
        vm.stopPrank();

        positionManager.setCollateralEnabled(collateralTokenSecond, false);

        (,,,, raftCollateralTokenSecondEnabled,,,,,) = positionManager.collateralInfo(collateralTokenSecond);
        assertFalse(raftCollateralTokenSecondEnabled);

        // Alice can still withdraw R
        vm.prank(ALICE);
        positionManager.managePosition(
            collateralToken, ALICE, 0, false, 1, true, MathUtils._100_PERCENT, emptySignature
        );

        // Bob cannot withdraw more R
        vm.prank(BOB);
        vm.expectRevert(IPositionManager.CollateralTokenDisabled.selector);
        positionManager.managePosition(
            collateralTokenSecond, BOB, 0, false, 1, true, MathUtils._100_PERCENT, emptySignature
        );

        // Bob can execute other operations
        vm.startPrank(BOB);
        collateralTokenSecond.approve(address(positionManager), 1);
        positionManager.managePosition(collateralTokenSecond, BOB, 1, true, 0, false, 0, emptySignature);
        positionManager.managePosition(collateralTokenSecond, BOB, 1, false, 0, false, 0, emptySignature);
        positionManager.managePosition(collateralTokenSecond, BOB, 0, false, 1, false, 0, emptySignature);
        vm.stopPrank();

        // Carol cannot open a position with the disabled collateral token and withdraw R
        vm.startPrank(CAROL);
        collateralTokenSecond.approve(address(positionManager), 1 ether);
        vm.expectRevert(IPositionManager.CollateralTokenDisabled.selector);
        positionManager.managePosition(collateralTokenSecond, CAROL, 1 ether, true, 1, true, 0, emptySignature);
        vm.stopPrank();
    }

    function testInvalidCollateralTokenModification() public {
        vm.prank(randomAddress);
        vm.expectRevert("Ownable: caller is not the owner");
        positionManager.setCollateralEnabled(collateralToken, false);

        TokenMock collateralTokenThird = new TokenMock();
        vm.expectRevert(IPositionManager.CollateralTokenNotAdded.selector);
        positionManager.setCollateralEnabled(collateralTokenThird, true);
    }
}
