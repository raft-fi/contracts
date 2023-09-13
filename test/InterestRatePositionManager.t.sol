// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { PriceFeedTestnet } from "./mocks/PriceFeedTestnet.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { IRToken } from "../contracts/Interfaces/IRToken.sol";
import { IPositionManager } from "../contracts/Interfaces/IPositionManager.sol";
import {
    IInterestRatePositionManager,
    InterestRatePositionManager
} from "../contracts/InterestRates/InterestRatePositionManager.sol";
import { InterestRateDebtToken } from "../contracts/InterestRates/InterestRateDebtToken.sol";
import { IERC20Indexable } from "../contracts/Interfaces/IERC20Indexable.sol";
import { ERC20Indexable } from "../contracts/ERC20Indexable.sol";
import { SplitLiquidationCollateral } from "../contracts/SplitLiquidationCollateral.sol";
import { IPSM } from "../contracts/PSM/IPSM.sol";
import { IChai } from "../contracts/PSM/IChai.sol";
import { ILock } from "../contracts/common/ILock.sol";
import { ChaiPSM } from "../contracts/PSM/ChaiPSM.sol";
import { ConstantPriceFeed } from "../contracts/common/ConstantPriceFeed.sol";
import { PSMFixedFee } from "../contracts/PSM/FixedFee.sol";
import { PSMSplitLiquidationCollateral } from "../contracts/common/PSMSplitLiquidationCollateral.sol";
import { ERC20Capped } from "../contracts/common/ERC20Capped.sol";
import { WstETHTokenMock } from "./mocks/WstETHTokenMock.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";
import "forge-std/console.sol";

contract InterestRatePositionManagerTests is Test {
    IRToken public constant R = IRToken(address(0x183015a9bA6fF60230fdEaDc3F43b3D788b13e21));
    address public constant OWNER = address(0xaB40A7e3cEF4AfB323cE23B6565012Ac7c76BFef);
    // User accounts
    address public constant ALICE = address(1);
    address public constant BOB = address(2);
    // WETH
    PriceFeedTestnet public wethPriceFeed;
    IERC20 public constant WETH = IERC20(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    // WstETH
    PriceFeedTestnet public wstethPriceFeed;
    WstETHTokenMock public wstETH;
    // swETH
    PriceFeedTestnet public swethPriceFeed;
    WstETHTokenMock public swETH;

    InterestRatePositionManager public irPosman;
    uint256 public constant CAP = 10_000e18;
    uint256 public constant INDEX_INC_PER_SEC = 1e10;
    address public constant WHALE = address(0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E);

    function setUp() public {
        vm.createSelectFork("mainnet", 18_004_964);
        wethPriceFeed = new PriceFeedTestnet();
        wethPriceFeed.setPrice(1000e18);
        wstETH = new WstETHTokenMock();
        wstethPriceFeed = new PriceFeedTestnet();
        wstethPriceFeed.setPrice(1000e18);
        swETH = new WstETHTokenMock();
        swethPriceFeed = new PriceFeedTestnet();
        swethPriceFeed.setPrice(1000e18);
        vm.startPrank(OWNER);
        irPosman = new InterestRatePositionManager(R);
        irPosman.positionManager().addCollateralToken(
            irPosman, new ConstantPriceFeed(address(irPosman)), new PSMSplitLiquidationCollateral()
        );
        irPosman.addCollateralToken(
            WETH,
            wethPriceFeed,
            new SplitLiquidationCollateral(),
            new ERC20Indexable(address(irPosman), "Raft WETH collateral", "rWETH-c", type(uint256).max),
            new InterestRateDebtToken(address(irPosman), "Raft WETH debt", "rWETH-d", WETH, CAP, INDEX_INC_PER_SEC)
        );
        irPosman.addCollateralToken(
            wstETH,
            wstethPriceFeed,
            new SplitLiquidationCollateral(),
            new ERC20Indexable(address(irPosman), "Raft WstETH collateral", "rWstETH-c", type(uint256).max),
            new InterestRateDebtToken(
                address(irPosman), "Raft WstETH debt", "rWstETH-d", wstETH, CAP, INDEX_INC_PER_SEC
            )
        );
        irPosman.addCollateralToken(
            swETH,
            swethPriceFeed,
            new SplitLiquidationCollateral(),
            new ERC20Indexable(address(irPosman), "Raft swETH collateral", "rswETH-c", type(uint256).max),
            new InterestRateDebtToken(
                address(irPosman), "Raft swETH debt", "rswETH-d", swETH, CAP, INDEX_INC_PER_SEC
            )
        );
        vm.stopPrank();

        wstETH.mint(ALICE, 10e36);
        wstETH.mint(BOB, 10e36);
    }

    function testFeesPaidAndInterestAccrues() public {
        ERC20PermitSignature memory emptySignature;
        uint256 debtAmount = 4000e18;

        vm.startPrank(WHALE);
        WETH.approve(address(irPosman), 6e18);
        irPosman.managePosition(WETH, WHALE, 6e18, true, debtAmount, true, 0, emptySignature);
        vm.stopPrank();

        uint256 currentTime = block.timestamp;
        vm.warp(currentTime + 10 days);
        uint256 debtAfter = irPosman.raftDebtToken(WETH).balanceOf(WHALE);
        assertGt(debtAfter, debtAmount);
        uint256 totalFees = debtAfter - debtAmount;
        InterestRateDebtToken(address(irPosman.raftDebtToken(WETH))).updateIndexAndPayFees();
        uint256 expectedTotalFees = debtAmount * INDEX_INC_PER_SEC * (10 days) / 1e18;
        assertGe(R.balanceOf(OWNER), totalFees);
        assertEq(totalFees, expectedTotalFees);
    }

    function testMintingFailsAfterCapReached() public {
        ERC20PermitSignature memory emptySignature;

        vm.startPrank(WHALE);
        WETH.approve(address(irPosman), 20e18);
        irPosman.managePosition(WETH, WHALE, 20e18, true, CAP - 1e18, true, 0, emptySignature);

        uint256 currentTime = block.timestamp;
        vm.warp(currentTime + 10 days);

        vm.expectRevert(ERC20Capped.ERC20ExceededCap.selector);
        irPosman.managePosition(WETH, WHALE, 0, false, 1e18, true, 0, emptySignature);
        vm.stopPrank();
    }

    function testMintFeesInvalidCaller() public {
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IInterestRatePositionManager.InvalidDebtToken.selector, OWNER));
        irPosman.mintFees(WETH, 1);
    }

    function testSuccessfulOpenPosition() public {
        // Alice transaction
        vm.startPrank(ALICE);
        uint256 aliceCollateralAmount = 10e18;
        uint256 aliceDebtAmount = 5000e18;
        wstETH.approve(address(irPosman), aliceCollateralAmount);
        ERC20PermitSignature memory emptySignature;
        irPosman.managePosition(wstETH, ALICE, aliceCollateralAmount, true, aliceDebtAmount, true, 0, emptySignature);
        // Alice checks
        (, IERC20Indexable wstETHDebtToken,,,,,,,,) = irPosman.collateralInfo(wstETH);
        assertEq(wstETHDebtToken.currentIndex(), 1e18);
        assertEq(wstETHDebtToken.balanceOf(ALICE), aliceDebtAmount);
        assertEq(R.balanceOf(ALICE), aliceDebtAmount);
        uint256 currentAliceICR =
            PositionManagerUtils.getCurrentICR(irPosman, wstETH, ALICE, wstethPriceFeed.getPrice());
        assertEq(currentAliceICR, 2e18);
        assertEq(R.balanceOf(irPosman.feeRecipient()), 0); // There is no fees yet
        assertEq(wstETHDebtToken.totalSupply(), aliceDebtAmount);
        vm.stopPrank();

        uint256 timestampWarp = 10_000;
        vm.warp(block.timestamp + timestampWarp);

        // Bob transaction
        vm.startPrank(BOB);
        uint256 bobCollateralAmount = 8e18;
        uint256 bobDebtAmount = 4000e18;
        wstETH.approve(address(irPosman), bobCollateralAmount);
        uint256 totalFeesBeforeTransaction = R.balanceOf(irPosman.feeRecipient());
        irPosman.managePosition(wstETH, BOB, bobCollateralAmount, true, bobDebtAmount, true, 0, emptySignature);
        // Alice and Bob checks
        assertEq(wstETHDebtToken.currentIndex(), 1e18 + timestampWarp * INDEX_INC_PER_SEC);
        uint256 newAliceDebtAmount = aliceDebtAmount * (1e18 + timestampWarp * INDEX_INC_PER_SEC) / 1e18;
        assertEq(wstETHDebtToken.balanceOf(ALICE), newAliceDebtAmount);
        assertEq(R.balanceOf(ALICE), aliceDebtAmount);
        currentAliceICR = PositionManagerUtils.getCurrentICR(irPosman, wstETH, ALICE, wstethPriceFeed.getPrice());
        assertLt(currentAliceICR, 2e18);
        assertEq(wstETHDebtToken.balanceOf(BOB), bobDebtAmount);
        assertEq(R.balanceOf(BOB), bobDebtAmount);
        uint256 currentBobICR = PositionManagerUtils.getCurrentICR(irPosman, wstETH, BOB, wstethPriceFeed.getPrice());
        assertEq(currentBobICR, 2e18);
        assertGt(R.balanceOf(irPosman.feeRecipient()), totalFeesBeforeTransaction);
        assertEq(wstETHDebtToken.totalSupply(), newAliceDebtAmount + bobDebtAmount);
        vm.stopPrank();

        timestampWarp = 5000;
        vm.warp(block.timestamp + timestampWarp);

        // Whale transaction
        vm.startPrank(WHALE);
        uint256 whaleCollateralAmount = 6e18;
        uint256 whaleDebtAmount = 4000e18;
        WETH.approve(address(irPosman), whaleCollateralAmount);
        totalFeesBeforeTransaction = R.balanceOf(irPosman.feeRecipient());
        irPosman.managePosition(WETH, WHALE, whaleCollateralAmount, true, whaleDebtAmount, true, 0, emptySignature);
        assertEq(R.balanceOf(irPosman.feeRecipient()), totalFeesBeforeTransaction); // Because it is the first
            // transaction with WETH, there is no fees yet
        assertEq(R.balanceOf(WHALE), whaleDebtAmount);
        vm.stopPrank();

        timestampWarp = 5000;
        vm.warp(block.timestamp + timestampWarp);

        vm.startPrank(WHALE);
        WETH.approve(address(irPosman), whaleCollateralAmount);
        totalFeesBeforeTransaction = R.balanceOf(irPosman.feeRecipient());
        irPosman.managePosition(WETH, WHALE, whaleCollateralAmount, true, whaleDebtAmount, true, 0, emptySignature);
        assertGt(R.balanceOf(irPosman.feeRecipient()), totalFeesBeforeTransaction);
        assertEq(R.balanceOf(WHALE), whaleDebtAmount * 2); // Two transactions with the same amount, so that is why
            // multiply by 2
        vm.stopPrank();
    }

    function testSuccessfulClosePosition() public {
        vm.startPrank(ALICE);
        uint256 aliceCollateralAmount = 10e18;
        uint256 aliceInitialDebtAmount = 5000e18;
        wstETH.approve(address(irPosman), aliceCollateralAmount);
        ERC20PermitSignature memory emptySignature;
        irPosman.managePosition(
            wstETH, ALICE, aliceCollateralAmount, true, aliceInitialDebtAmount, true, 0, emptySignature
        );
        vm.stopPrank();

        uint256 timestampWarp = 10_000;
        vm.warp(block.timestamp + timestampWarp);

        vm.startPrank(BOB);
        uint256 bobCollateralAmount = 8e18;
        uint256 bobDebtAmount = 4000e18;
        wstETH.approve(address(irPosman), bobCollateralAmount);
        uint256 totalFeesBeforeTransaction = R.balanceOf(irPosman.feeRecipient());
        irPosman.managePosition(wstETH, BOB, bobCollateralAmount, true, bobDebtAmount, true, 0, emptySignature);
        vm.stopPrank();

        timestampWarp = 10_000;
        vm.warp(block.timestamp + timestampWarp);

        vm.startPrank(WHALE);
        uint256 whaleCollateralAmount = 6e18;
        uint256 whaleDebtAmount = 4000e18;
        WETH.approve(address(irPosman), whaleCollateralAmount);
        totalFeesBeforeTransaction = R.balanceOf(irPosman.feeRecipient());
        irPosman.managePosition(WETH, WHALE, whaleCollateralAmount, true, whaleDebtAmount, true, 0, emptySignature);
        vm.stopPrank();

        timestampWarp = 5000;
        vm.warp(block.timestamp + timestampWarp);

        // Alice close position transaction
        vm.startPrank(ALICE);
        (IERC20Indexable wstETHCollateralToken, IERC20Indexable wstETHDebtToken,,,,,,,,) =
            irPosman.collateralInfo(wstETH);
        uint256 newAliceDebtAmount = aliceInitialDebtAmount * (1e18 + timestampWarp * INDEX_INC_PER_SEC) / 1e18;
        assertGt(wstETHDebtToken.balanceOf(ALICE), newAliceDebtAmount);
        R.approve(address(irPosman), type(uint256).max);
        console.log("aliceDebtAmount", newAliceDebtAmount);
        console.log("aliceRBalanceBefore", R.balanceOf(ALICE)); // 5000e18
        // Trying to send more R than Alice has (debt amount, not R amount)
        irPosman.managePosition(wstETH, ALICE, 0, false, type(uint256).max, false, 0, emptySignature);
        //uint256 aliceCollateralAfter = collateralToken.balanceOf(ALICE);
        //uint256 aliceDebtAfter = raftDebtToken.balanceOf(ALICE);
        //uint256 aliceDebtBalanceAfter = rToken.balanceOf(ALICE);
        //uint256 bobPositionCollateralAfter = raftCollateralToken.balanceOf(BOB);
        //uint256 positionManagerCollateralBalance = collateralToken.balanceOf(address(positionManager));
        //assertEq(wstETHCollateralToken.balanceOf(ALICE), 0);
        //assertEq(aliceDebtAfter, 0);
        //assertEq(positionManagerCollateralBalance, bobPositionCollateralAfter);
        //assertEq(aliceCollateralAfter, aliceCollateralBefore);
        //assertEq(aliceDebtBalanceAfter, aliceRBalanceBefore - aliceDebtBefore);
        vm.stopPrank();
    }
}
