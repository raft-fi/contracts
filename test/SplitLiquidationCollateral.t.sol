// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {SplitLiquidationCollateral} from "../contracts/SplitLiquidationCollateral.sol";
import {Test} from "forge-std/Test.sol";

contract SplitLiquidationCollateralTest is Test {
    SplitLiquidationCollateral public splitLiquidationCollateral;

    function setUp() public {
        splitLiquidationCollateral = new SplitLiquidationCollateral();
    }

    function testSplitRedistribution() public {
        uint256 collateralAmount = 1_000e18;
        (, uint256 collateralToSentToLiquidator) = splitLiquidationCollateral.split(collateralAmount, 0, 0, true, 0);
        assertEq(collateralToSentToLiquidator, 30e18); // 1000 * 3%

        collateralAmount = 10_000e18;
        (, collateralToSentToLiquidator) = splitLiquidationCollateral.split(collateralAmount, 0, 0, true, 0);
        assertApproxEqAbs(collateralToSentToLiquidator, 287e18, 1e18);

        collateralAmount = 100_000e18;
        (, collateralToSentToLiquidator) = splitLiquidationCollateral.split(collateralAmount, 0, 0, true, 0);
        assertEq(collateralToSentToLiquidator, 1_250e18);

        collateralAmount = 500_000e18;
        (, collateralToSentToLiquidator) = splitLiquidationCollateral.split(collateralAmount, 0, 0, true, 0);
        assertApproxEqAbs(collateralToSentToLiquidator, 4_583e18, 1e18);

        collateralAmount = 1_000_000e18;
        (, collateralToSentToLiquidator) = splitLiquidationCollateral.split(collateralAmount, 0, 0, true, 0);
        assertEq(collateralToSentToLiquidator, 5_000e18);

        collateralAmount = 2_000_000e18;
        (, collateralToSentToLiquidator) = splitLiquidationCollateral.split(collateralAmount, 0, 0, true, 0);
        assertEq(collateralToSentToLiquidator, 10_000e18);
    }
}
