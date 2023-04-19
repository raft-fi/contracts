// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Fixed256x18} from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";

library MathUtils {
    // --- Constants ---

    /// @notice Represents 100%.
    /// @dev 1e18 is the scaling factor (100% == 1e18).
    uint256 public constant _100_PERCENT = Fixed256x18.ONE;

    /// @notice Minimum collateral ratio for individual positions.
    uint256 public constant MCR = 110 * _100_PERCENT / 100; // 110%

    /// @notice Precision for Nominal ICR (independent of price).
    /// @dev Rationale for the value:
    /// - Making it “too high” could lead to overflows.
    /// - Making it “too low” could lead to an ICR equal to zero, due to truncation from floor division.
    ///
    /// This value of 1e20 is chosen for safety: the NICR will only overflow for numerator > ~1e39 collateralToken,
    /// and will only truncate to 0 if the denominator is at least 1e20 times greater than the numerator.
    uint256 internal constant _NICR_PRECISION = 1e20;

    /// @notice Number of minutes in 1000 years.
    uint256 internal constant _MINUTES_IN_1000_YEARS = 1000 * 356 days / 1 minutes;

    // --- Functions ---

    /// @notice Multiplies two decimal numbers and use normal rounding rules:
    /// - round product up if 19'th mantissa digit >= 5
    /// - round product down if 19'th mantissa digit < 5.
    /// @param x First number.
    /// @param y Second number.
    function _decMul(uint256 x, uint256 y) internal pure returns (uint256 decProd) {
        decProd = (x * y + Fixed256x18.ONE / 2) / Fixed256x18.ONE;
    }

    /// @notice Exponentiation function for 18-digit decimal base, and integer exponent n.
    ///
    /// @dev Uses the efficient "exponentiation by squaring" algorithm. O(log(n)) complexity. The exponent is capped to
    /// avoid reverting due to overflow.
    ///
    /// If a period of > 1000 years is ever used as an exponent in either of the above functions, the result will be
    /// negligibly different from just passing the cap, since the decayed base rate will be 0 for 1000 years or > 1000
    /// years.
    /// @param base The decimal base.
    /// @param exponent The exponent.
    /// @return The result of the exponentiation.
    function _decPow(uint256 base, uint256 exponent) internal pure returns (uint256) {
        if (exponent == 0) {
            return Fixed256x18.ONE;
        }

        uint256 y = Fixed256x18.ONE;
        uint256 x = base;
        uint256 n = Math.min(exponent, _MINUTES_IN_1000_YEARS); // cap to avoid overflow

        // Exponentiation-by-squaring
        while (n > 1) {
            if (n % 2 != 0) {
                y = _decMul(x, y);
            }
            x = _decMul(x, x);
            n /= 2;
        }

        return _decMul(x, y);
    }

    /// @notice Computes the Nominal Individual Collateral Ratio (NICR) for given collateral and debt. If debt is zero,
    /// it returns the maximal value for uint256 (represents "infinite" CR).
    /// @param collateral Collateral amount.
    /// @param debt Debt amount.
    /// @return NICR.
    function _computeNominalCR(uint256 collateral, uint256 debt) internal pure returns (uint256) {
        return debt > 0 ? collateral * _NICR_PRECISION / debt : type(uint256).max;
    }

    /// @notice Computes the Collateral Ratio for given collateral, debt and price. If debt is zero, it returns the
    /// maximal value for uint256 (represents "infinite" CR).
    /// @param collateral Collateral amount.
    /// @param debt Debt amount.
    /// @param price Collateral price.
    /// @return Collateral ratio.
    function _computeCR(uint256 collateral, uint256 debt, uint256 price) internal pure returns (uint256) {
        return debt > 0 ? collateral * price / debt : type(uint256).max;
    }
}
