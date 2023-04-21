// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Indexable } from "../contracts/Interfaces/IERC20Indexable.sol";
import { IPositionManager } from "../contracts/Interfaces/IPositionManager.sol";
import { PositionManager } from "../contracts/PositionManager.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { PriceFeedTestnet } from "./TestContracts/PriceFeedTestnet.sol";
import { TokenMock } from "./TestContracts/TokenMock.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";

contract PositionManagerMultiCollateralTest is TestSetup {
    uint256 public constant DEFAULT_PRICE = 200e18;

    PriceFeedTestnet public priceFeed;
    IPositionManager public positionManager;

    TokenMock public collateralTokenSecond;
    PriceFeedTestnet public priceFeedSecond;

    address public randomAddress;

    function setUp() public override {
        super.setUp();

        positionManager = new PositionManager(
            new address[](0),
            splitLiquidationCollateral
        );

        priceFeed = new PriceFeedTestnet();
        positionManager.addCollateralToken(collateralToken, priceFeed);

        collateralTokenSecond = new TokenMock();
        priceFeedSecond = new PriceFeedTestnet();
        positionManager.addCollateralToken(collateralTokenSecond, priceFeedSecond);

        randomAddress = makeAddr("randomAddress");

        collateralToken.mint(ALICE, 10e36);
        collateralToken.mint(BOB, 10e36);
        collateralToken.mint(CAROL, 10e36);
    }

    function testAddCollateralToken() public {
        TokenMock collateralTokenThird = new TokenMock();
        PriceFeedTestnet priceFeedThird = new PriceFeedTestnet();

        (IERC20Indexable raftCollateralTokenThird, bool raftCollateralTokenThirdEnabled) =
            positionManager.raftCollateralTokens(collateralTokenThird);
        assertEq(address(raftCollateralTokenThird), address(0));
        assertFalse(raftCollateralTokenThirdEnabled);

        positionManager.addCollateralToken(collateralTokenThird, priceFeedThird);

        (raftCollateralTokenThird, raftCollateralTokenThirdEnabled) =
            positionManager.raftCollateralTokens(collateralTokenThird);
        assertTrue(raftCollateralTokenThird != IERC20(address(0)));
        assertTrue(raftCollateralTokenThirdEnabled);
    }

    function testCannotAddCollateralToken() public {
        vm.expectRevert(IPositionManager.CollateralTokenAlreadyAdded.selector);
        positionManager.addCollateralToken(collateralTokenSecond, priceFeedSecond);

        TokenMock collateralTokenThird = new TokenMock();
        PriceFeedTestnet priceFeedThird = new PriceFeedTestnet();
        vm.prank(randomAddress);
        vm.expectRevert("Ownable: caller is not the owner");
        positionManager.addCollateralToken(collateralTokenThird, priceFeedThird);
    }

    function testDisabledCollateralToken() public {
        (, bool raftCollateralTokenFirstEnabled) = positionManager.raftCollateralTokens(collateralToken);
        assertTrue(raftCollateralTokenFirstEnabled);

        (, bool raftCollateralTokenSecondEnabled) = positionManager.raftCollateralTokens(collateralTokenSecond);
        assertTrue(raftCollateralTokenSecondEnabled);

        collateralTokenSecond.mint(BOB, 10e36);
        collateralTokenSecond.mint(CAROL, 10e36);

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
            collateralToken: collateralTokenSecond,
            extraDebtAmount: 1e18,
            icr: 2e18
        });
        vm.stopPrank();

        positionManager.modifyCollateralToken(collateralTokenSecond, false);

        (, raftCollateralTokenSecondEnabled) = positionManager.raftCollateralTokens(collateralTokenSecond);
        assertFalse(raftCollateralTokenSecondEnabled);

        // Alice can still withdraw R
        vm.prank(ALICE);
        positionManager.managePosition(collateralToken, 0, false, 1, true, MathUtils._100_PERCENT);

        // Bob cannot withdraw more R
        vm.prank(BOB);
        vm.expectRevert(IPositionManager.CollateralTokenDisabled.selector);
        positionManager.managePosition(collateralTokenSecond, 0, false, 1, true, MathUtils._100_PERCENT);

        // Bob can execute other operations
        vm.startPrank(BOB);
        collateralTokenSecond.approve(address(positionManager), 1);
        positionManager.managePosition(collateralTokenSecond, 1, true, 0, false, 0);
        positionManager.managePosition(collateralTokenSecond, 1, false, 0, false, 0);
        positionManager.managePosition(collateralTokenSecond, 0, false, 1, false, 0);
        vm.stopPrank();

        // Carol cannot open a position with the disabled collateral token and withdraw R
        vm.startPrank(CAROL);
        collateralTokenSecond.approve(address(positionManager), 1 ether);
        vm.expectRevert(IPositionManager.CollateralTokenDisabled.selector);
        positionManager.managePosition(collateralTokenSecond, 1 ether, true, 1, true, 0);
        vm.stopPrank();
    }

    function testInvalidCollateralTokenModification() public {
        vm.prank(randomAddress);
        vm.expectRevert("Ownable: caller is not the owner");
        positionManager.modifyCollateralToken(collateralToken, false);

        TokenMock collateralTokenThird = new TokenMock();
        vm.expectRevert(IPositionManager.CollateralTokenNotAdded.selector);
        positionManager.modifyCollateralToken(collateralTokenThird, true);
    }
}
