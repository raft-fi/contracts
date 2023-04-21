// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { SplitLiquidationCollateral } from "../contracts/SplitLiquidationCollateral.sol";
import { Test } from "forge-std/Test.sol";

contract SplitLiquidationCollateralTest is Test {
    SplitLiquidationCollateral public splitLiquidationCollateral;

    function setUp() public {
        splitLiquidationCollateral = new SplitLiquidationCollateral();
    }

    function testSplitRedistribution() public {
        uint256 collateralAmount = 1000e18;
        (, uint256 collateralToSentToLiquidator) = splitLiquidationCollateral.split(collateralAmount, 0, 1e18, true);
        assertEq(collateralToSentToLiquidator, 30e18); // 1000 * 3%

        collateralAmount = 10_000e18;
        (, collateralToSentToLiquidator) = splitLiquidationCollateral.split(collateralAmount, 0, 1e18, true);
        assertApproxEqAbs(collateralToSentToLiquidator, 287e18, 1e18);

        collateralAmount = 100_000e18;
        (, collateralToSentToLiquidator) = splitLiquidationCollateral.split(collateralAmount, 0, 1e18, true);
        assertEq(collateralToSentToLiquidator, 1250e18);

        collateralAmount = 500_000e18;
        (, collateralToSentToLiquidator) = splitLiquidationCollateral.split(collateralAmount, 0, 1e18, true);
        assertApproxEqAbs(collateralToSentToLiquidator, 4583e18, 1e18);

        collateralAmount = 1_000_000e18;
        (, collateralToSentToLiquidator) = splitLiquidationCollateral.split(collateralAmount, 0, 1e18, true);
        assertEq(collateralToSentToLiquidator, 5000e18);

        collateralAmount = 2_000_000e18;
        (, collateralToSentToLiquidator) = splitLiquidationCollateral.split(collateralAmount, 0, 1e18, true);
        assertEq(collateralToSentToLiquidator, 10_000e18);
    }

    function testSplitLiquidation() public {
        uint256 collateralAmount = 500e18;
        uint256 debtAmount = 1000e18;
        uint256 price = 5e18;
        (uint256 collateralToSendToProtocol, uint256 collateralToSentToLiquidator) =
            splitLiquidationCollateral.split(collateralAmount, debtAmount, price, false);
        assertEq(collateralToSendToProtocol, 0);
        assertEq(collateralToSentToLiquidator, 300e18); // 100% of 300e18 (collateralAmount - debtAmount / price)

        collateralAmount = 1000e18;
        debtAmount = 3000e18;
        price = 5e18;
        (collateralToSendToProtocol, collateralToSentToLiquidator) =
            splitLiquidationCollateral.split(collateralAmount, debtAmount, price, false);
        assertEq(collateralToSendToProtocol, 0);
        assertEq(collateralToSentToLiquidator, 400e18); // 100% of 400e18 (collateralAmount - debtAmount / price)

        collateralAmount = 5000e18;
        debtAmount = 10_000e18;
        price = 5e18;
        (collateralToSendToProtocol, collateralToSentToLiquidator) =
            splitLiquidationCollateral.split(collateralAmount, debtAmount, price, false);
        // (collateralAmount - debtAmount / price) - collateralToSentToLiquidator
        assertApproxEqAbs(collateralToSendToProtocol, 3000e18 - 2925e18, 1e18);
        // 97.5% of 3000e18 (collateralAmount - debtAmount / price)
        assertApproxEqAbs(collateralToSentToLiquidator, 2925e18, 1e18);

        collateralAmount = 50_000e18;
        debtAmount = 100_000e18;
        price = 5e18;
        (collateralToSendToProtocol, collateralToSentToLiquidator) =
            splitLiquidationCollateral.split(collateralAmount, debtAmount, price, false);
        assertEq(collateralToSendToProtocol, 10_500e18); // 30_000e18 - collateralToSentToLiquidator
        assertEq(collateralToSentToLiquidator, 19_500e18); // 65% of 30_000e18 (collateralAmount - debtAmount / price)

        collateralAmount = 500_000e18;
        debtAmount = 1_000_000e18;
        price = 5e18;
        (collateralToSendToProtocol, collateralToSentToLiquidator) =
            splitLiquidationCollateral.split(collateralAmount, debtAmount, price, false);
        assertEq(collateralToSendToProtocol, 150_000e18); // 300_000e18 - collateralToSentToLiquidator
        assertEq(collateralToSentToLiquidator, 150_000e18); // 50% of 50_000e18 (collateralAmount - debtAmount / price)

        collateralAmount = 5_000_000e18;
        debtAmount = 10_000_000e18;
        price = 5e18;
        (collateralToSendToProtocol, collateralToSentToLiquidator) =
            splitLiquidationCollateral.split(collateralAmount, debtAmount, price, false);
        assertEq(collateralToSendToProtocol, 1_500_000e18); // 3_000_000e18 - collateralToSentToLiquidator
        // 50% of 3_000_000e18 (collateralAmount - debtAmount / price)
        assertEq(collateralToSentToLiquidator, 1_500_000e18);
    }
}
