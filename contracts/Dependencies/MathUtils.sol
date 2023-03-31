// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @dev Fee exceeded provided maximum fee percentage
error FeeExceedsMaxFee(uint fee, uint amount, uint maxFeePercentage);

library MathUtils {
    uint constant public DECIMAL_PRECISION = 1e18;

    uint constant public MINUTES_IN_1000_YEARS = 1000 * 356 days / 1 minutes;

    uint constant public _100pct = 1000000000000000000; // 1e18 == 100%

    // Minimum collateral ratio for individual positions
    uint constant public MCR = 1100000000000000000; // 110%

    // Amount of R to be locked in gas pool on opening positions
    uint constant public R_GAS_COMPENSATION = 200e18;

    // Minimum amount of net R debt a position must have
    uint constant public MIN_NET_DEBT = 1800e18;

    uint constant public PERCENT_DIVISOR = 200; // dividing by 200 yields 0.5%

    /* Precision for Nominal ICR (independent of price). Rationale for the value:
     *
     * - Making it “too high” could lead to overflows.
     * - Making it “too low” could lead to an ICR equal to zero, due to truncation from Solidity floor division.
     *
     * This value of 1e20 is chosen for safety: the NICR will only overflow for numerator > ~1e39 collateralToken,
     * and will only truncate to 0 if the denominator is at least 1e20 times greater than the numerator.
     *
     */
    uint internal constant NICR_PRECISION = 1e20;

    /*
    * Multiply two decimal numbers and use normal rounding rules:
    * -round product up if 19'th mantissa digit >= 5
    * -round product down if 19'th mantissa digit < 5
    *
    * Used only inside the exponentiation, decPow().
    */
    function decMul(uint x, uint y) internal pure returns (uint decProd) {
        decProd = (x * y + DECIMAL_PRECISION / 2) / DECIMAL_PRECISION;
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
    function decPow(uint _base, uint _minutes) internal pure returns (uint) {
        if (_minutes > MINUTES_IN_1000_YEARS) {_minutes = MINUTES_IN_1000_YEARS;}  // cap to avoid overflow

        if (_minutes == 0) {return DECIMAL_PRECISION;}

        uint y = DECIMAL_PRECISION;
        uint x = _base;
        uint n = _minutes;

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

    function computeNominalCR(uint _coll, uint _debt) internal pure returns (uint) {
        if (_debt > 0) {
            return _coll * NICR_PRECISION / _debt;
        }

        // Return the maximal value for uint256 if the Position has a debt of 0. Represents "infinite" CR.
        return type(uint).max;
    }

    function computeCR(uint _coll, uint _debt, uint _price) internal pure returns (uint) {
        if (_debt > 0) {
            return _coll * _price / _debt;
        }

        // Return the maximal value for uint256 if the Position has a debt of 0. Represents "infinite" CR.
        return type(uint).max;
    }

    // --- Gas compensation functions ---

    // Returns the composite debt (drawn debt + gas compensation) of a position, for the purpose of ICR calculation
    function getCompositeDebt(uint _debt) internal pure returns (uint) {
        return _debt + R_GAS_COMPENSATION;
    }

    function getNetDebt(uint _debt) internal pure returns (uint) {
        return _debt - R_GAS_COMPENSATION;
    }

    // Return the amount of collateralToken to be drawn from a position's collateral and sent as gas compensation.
    function getCollGasCompensation(uint _entireColl) internal pure returns (uint) {
        return _entireColl / PERCENT_DIVISOR;
    }

    function checkIfValidFee(uint _fee, uint _amount, uint _maxFeePercentage) internal pure {
        uint feePercentage = _fee * DECIMAL_PRECISION / _amount;

        if (feePercentage > _maxFeePercentage) {
            revert FeeExceedsMaxFee(_fee, _amount, _maxFeePercentage);
        }
    }
}
