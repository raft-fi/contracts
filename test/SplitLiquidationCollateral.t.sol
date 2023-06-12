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
        assertEq(collateralToSentToLiquidator, 500e18); // 100% of 300e18 + matching collateral

        collateralAmount = 1000e18;
        debtAmount = 3000e18;
        price = 5e18;
        (collateralToSendToProtocol, collateralToSentToLiquidator) =
            splitLiquidationCollateral.split(collateralAmount, debtAmount, price, false);
        assertEq(collateralToSendToProtocol, 0);
        assertEq(collateralToSentToLiquidator, 1000e18);

        collateralAmount = 5000e18;
        debtAmount = 10_000e18;
        price = 5e18;
        (collateralToSendToProtocol, collateralToSentToLiquidator) =
            splitLiquidationCollateral.split(collateralAmount, debtAmount, price, false);
        // (collateralAmount - debtAmount / price) - collateralToSentToLiquidator
        assertEq(collateralToSendToProtocol, 0);
        // 97.5% of 3000e18 (collateralAmount - debtAmount / price)
        assertEq(collateralToSentToLiquidator, collateralAmount - collateralToSendToProtocol);

        collateralAmount = 50_000e18;
        debtAmount = 100_000e18;
        price = 5e18;
        (collateralToSendToProtocol, collateralToSentToLiquidator) =
            splitLiquidationCollateral.split(collateralAmount, debtAmount, price, false);
        assertEq(collateralToSendToProtocol, 0);
        assertEq(collateralToSentToLiquidator, collateralAmount - collateralToSendToProtocol);

        collateralAmount = 500_000e18;
        debtAmount = 1_000_000e18;
        price = 5e18;
        (collateralToSendToProtocol, collateralToSentToLiquidator) =
            splitLiquidationCollateral.split(collateralAmount, debtAmount, price, false);
        assertEq(collateralToSendToProtocol, 0);
        assertEq(collateralToSentToLiquidator, collateralAmount - collateralToSendToProtocol);

        collateralAmount = 5_000_000e18;
        debtAmount = 10_000_000e18;
        price = 5e18;
        (collateralToSendToProtocol, collateralToSentToLiquidator) =
            splitLiquidationCollateral.split(collateralAmount, debtAmount, price, false);
        assertEq(collateralToSendToProtocol, 0);
        assertEq(collateralToSentToLiquidator, collateralAmount - collateralToSendToProtocol);
    }

    function testFuzzSplitLiquidation(uint256 collateralAmount, uint256 price, uint256 cr) public {
        cr = bound(cr, 1e18 + 1, 1.1e18 - 1);
        price = bound(price, 1e16, 1e32);
        collateralAmount = bound(collateralAmount, 1e13, 1e30);

        // cr = collateralAmount * price / debt
        uint256 debtAmount = collateralAmount * price / cr;

        (uint256 collateralToProtocol, uint256 collateralToLiquidator) =
            splitLiquidationCollateral.split(collateralAmount, debtAmount, price, false);
        assertEq(collateralToProtocol + collateralToLiquidator, collateralAmount);
    }

    function testFuzzSplitRedistribution(uint256 collateralAmount, uint256 price, uint256 cr) public {
        cr = bound(cr, 1e5, 1e18 - 1);
        price = bound(price, 1e16, 1e32);
        collateralAmount = bound(collateralAmount, 1e13, 1e30);

        // cr = collateralAmount * price / debt
        uint256 debtAmount = collateralAmount * price / cr;
        (uint256 collateralToProtocol, uint256 collateralToLiquidator) =
            splitLiquidationCollateral.split(collateralAmount, debtAmount, price, true);
        assertEq(collateralToProtocol, 0);
        assertLt(collateralToLiquidator, collateralAmount);
    }
}
