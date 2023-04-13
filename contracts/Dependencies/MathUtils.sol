// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Fixed256x18} from "@tempus-labs/contracts/math/Fixed256x18.sol";

library MathUtils {
    uint256 public constant MINUTES_IN_1000_YEARS = 1000 * 356 days / 1 minutes;

    uint256 public constant _100_PERCENT = Fixed256x18.ONE;

    // Minimum collateral ratio for individual positions
    uint256 public constant MCR = 110 * _100_PERCENT / 100; // 110%

    /* Precision for Nominal ICR (independent of price). Rationale for the value:
     *
     * - Making it “too high” could lead to overflows.
     * - Making it “too low” could lead to an ICR equal to zero, due to truncation from Solidity floor division.
     *
     * This value of 1e20 is chosen for safety: the NICR will only overflow for numerator > ~1e39 collateralToken,
     * and will only truncate to 0 if the denominator is at least 1e20 times greater than the numerator.
     */
    uint256 internal constant NICR_PRECISION = 1e20;

    /*
    * Multiply two decimal numbers and use normal rounding rules:
    * -round product up if 19'th mantissa digit >= 5
    * -round product down if 19'th mantissa digit < 5
    *
    * Used only inside the exponentiation, decPow().
    */
    function decMul(uint256 x, uint256 y) internal pure returns (uint256 decProd) {
        decProd = (x * y + Fixed256x18.ONE / 2) / Fixed256x18.ONE;
    }

    /*
    * decPow: Exponentiation function for 18-digit decimal base, and integer exponent n.
    *
    * Uses the efficient "exponentiation by squaring" algorithm. O(log(n)) complexity.
    *
    * Called by two functions that represent time in units of minutes:
    * 1) PositionManager._calcDecayedBaseRate
    * 2) CommunityIssuance._getCumulativeIssuanceFraction
    *
    * The exponent is capped to avoid reverting due to overflow.
    *
    * If a period of > 1000 years is ever used as an exponent in either of the above functions, the result will be
    * negligibly different from just passing the cap, since:
    *
    * In function 1), the decayed base rate will be 0 for 1000 years or > 1000 years
    * In function 2), the difference in tokens issued at 1000 years and any time > 1000 years, will be negligible
    */
    function decPow(uint256 _base, uint256 _minutes) internal pure returns (uint256) {
        if (_minutes == 0) {
            return Fixed256x18.ONE;
        }

        uint256 y = Fixed256x18.ONE;
        uint256 x = _base;
        uint256 n = Math.min(_minutes, MINUTES_IN_1000_YEARS); // cap to avoid overflow;

        // Exponentiation-by-squaring
        while (n > 1) {
            if (n % 2 != 0) {
                y = decMul(x, y);
            }
            x = decMul(x, x);
            n /= 2;
        }

        return decMul(x, y);
    }

    function computeNominalCR(uint256 _coll, uint256 _debt) internal pure returns (uint256) {
        if (_debt > 0) {
            return _coll * NICR_PRECISION / _debt;
        }

        // Return the maximal value for uint256 if the Position has a debt of 0. Represents "infinite" CR.
        return type(uint256).max;
    }

    function computeCR(uint256 _coll, uint256 _debt, uint256 _price) internal pure returns (uint256) {
        if (_debt > 0) {
            return _coll * _price / _debt;
        }

        // Return the maximal value for uint256 if the Position has a debt of 0. Represents "infinite" CR.
        return type(uint256).max;
    }
}
