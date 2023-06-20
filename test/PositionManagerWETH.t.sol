// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Indexable } from "../contracts/Interfaces/IERC20Indexable.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { IPositionManager, PositionManager } from "../contracts/PositionManager.sol";
import { IERC20Wrapped, IWETH, IPositionManagerWETH, PositionManagerWETH } from "../contracts/PositionManagerWETH.sol";
import { SplitLiquidationCollateral } from "../contracts/SplitLiquidationCollateral.sol";
import { WrappedCollateralToken } from "../contracts/WrappedCollateralToken.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";
import { PriceFeedTestnet } from "./mocks/PriceFeedTestnet.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";

contract PositionManagerWETHTest is TestSetup {
    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    PriceFeedTestnet public priceFeed;
    PositionManagerWETH public positionManagerWETH;
    WrappedCollateralToken public wrappedCollateralToken;

    function setUp() public override {
        vm.createSelectFork("mainnet", 16_974_953);

        super.setUp();

        wrappedCollateralToken = new WrappedCollateralToken(
            IERC20(WETH_ADDRESS), "Wrapped Collateral Token", "WCT", 100_000_0e18, type(uint256).max
        );

        priceFeed = new PriceFeedTestnet();
        positionManager.addCollateralToken(wrappedCollateralToken, priceFeed, splitLiquidationCollateral);

        positionManagerWETH = new PositionManagerWETH(
            address(positionManager),
            IERC20Wrapped(address(wrappedCollateralToken))
        );

        vm.prank(ALICE);
        positionManager.whitelistDelegate(address(positionManagerWETH), true);
    }

    function testGetPositionETH() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory alicePosition = PositionManagerUtils.openPositionWETH({
            positionManagerWETH: positionManagerWETH,
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

    function testDepositETH() public {
        uint256 rBalanceBefore = positionManager.rToken().balanceOf(ALICE);
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory result = PositionManagerUtils.openPositionWETH({
            positionManagerWETH: positionManagerWETH,
            priceFeed: priceFeed,
            icr: 2 * MathUtils._100_PERCENT,
            extraDebt: 0
        });
        vm.stopPrank();
        assertGt(positionManager.rToken().balanceOf(ALICE), rBalanceBefore);

        (IERC20Indexable raftCollateralToken,,,,,,,,,) = positionManager.collateralInfo(wrappedCollateralToken);

        uint256 positionCollateralBefore = raftCollateralToken.balanceOf(ALICE);
        assertEq(positionCollateralBefore, result.collateral);

        uint256 positionManagerWETHBalanceBefore = wrappedCollateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerWETHBalanceBefore, result.collateral);

        uint256 collateralTopUpAmount = 1 ether;

        vm.startPrank(ALICE);
        positionManagerWETH.managePositionETH{ value: collateralTopUpAmount }(
            collateralTopUpAmount, true, 0, false, 0, emptySignature
        );
        vm.stopPrank();

        uint256 positionCollateralAfter = raftCollateralToken.balanceOf(ALICE);
        assertEq(positionCollateralAfter, positionCollateralBefore + collateralTopUpAmount);

        uint256 positionManagerWETHBalanceAfter = wrappedCollateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerWETHBalanceAfter, positionManagerWETHBalanceBefore + collateralTopUpAmount);
    }

    function testCannotDepositETH() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPositionWETH({
            positionManagerWETH: positionManagerWETH,
            priceFeed: priceFeed,
            icr: 2 * MathUtils._100_PERCENT,
            extraDebt: 0
        });
        vm.stopPrank();

        vm.startPrank(ALICE);
        vm.expectRevert(IPositionManagerWETH.CollateralChangeAmountDoesNotMatchETHValue.selector);
        positionManagerWETH.managePositionETH{ value: 1 }(2, true, 0, false, 0, emptySignature);
        vm.stopPrank();

        vm.startPrank(ALICE);
        vm.expectRevert(IPositionManager.NoCollateralOrDebtChange.selector);
        positionManagerWETH.managePositionETH{ value: 0 }(0, true, 0, false, 0, emptySignature);
        vm.stopPrank();

        vm.startPrank(ALICE);
        vm.expectRevert(IPositionManager.NoCollateralOrDebtChange.selector);
        positionManagerWETH.managePositionETH{ value: 10 }(0, false, 0, false, 0, emptySignature);
        vm.stopPrank();
    }

    // Sends the correct amount of ETH to the user
    function testWithdrawETH() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPositionWETH({
            positionManagerWETH: positionManagerWETH,
            priceFeed: priceFeed,
            icr: 2 * MathUtils._100_PERCENT,
            extraDebt: 0
        });
        vm.stopPrank();

        uint256 aliceBalanceBefore = ALICE.balance;
        uint256 withdrawAmount = 1 ether;

        // Alice withdraws 1 ETH
        vm.prank(ALICE);
        positionManagerWETH.managePositionETH(withdrawAmount, false, 0, false, 0, emptySignature);
        assertEq(ALICE.balance, aliceBalanceBefore + withdrawAmount);
    }

    function testWithdrawETHAsMaxDebt() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPositionWETH({
            positionManagerWETH: positionManagerWETH,
            priceFeed: priceFeed,
            icr: 2 * MathUtils._100_PERCENT,
            extraDebt: 0
        });
        vm.stopPrank();

        uint256 aliceBalanceBefore = ALICE.balance;
        uint256 withdrawAmount = 30 ether;

        // Alice withdraws max debt
        vm.startPrank(ALICE);
        positionManager.rToken().approve(address(positionManagerWETH), type(uint256).max);
        positionManagerWETH.managePositionETH(0, false, type(uint256).max, false, 0, emptySignature);
        vm.stopPrank();
        assertEq(ALICE.balance, aliceBalanceBefore + withdrawAmount);
    }

    // Sends the correct amount of ETH to the user
    function testWithdrawETHAlongWithRRepayment() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPositionWETH({
            positionManagerWETH: positionManagerWETH,
            priceFeed: priceFeed,
            icr: 2 * MathUtils._100_PERCENT,
            extraDebt: 2 ether
        });
        vm.stopPrank();

        uint256 aliceBalanceBefore = ALICE.balance;
        uint256 withdrawAmount = 1 ether;

        uint256 rBalanceBefore = positionManager.rToken().balanceOf(ALICE);

        // Alice withdraws 1 ETH
        vm.startPrank(ALICE);
        positionManager.rToken().approve(address(positionManagerWETH), 1 ether);
        positionManagerWETH.managePositionETH(withdrawAmount, false, 1 ether, false, 0, emptySignature);
        vm.stopPrank();

        assertEq(positionManager.rToken().balanceOf(ALICE), rBalanceBefore - 1 ether);
        assertEq(ALICE.balance, aliceBalanceBefore + withdrawAmount);
    }
}
