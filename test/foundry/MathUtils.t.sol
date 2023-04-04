// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../../contracts/Dependencies/MathUtils.sol";

contract MathUtilsTest is Test {
    // --- decPow() ---

    // For exponent = 0, returns 1, regardless of base
    function testDecPowExponentZero() public {
        uint120[7] memory bases =
            [0, 1, 1e18, 123244254546, 990000000000000000, 897890990909098978678609090, 8789789e27];

        for (uint256 i = 0; i < bases.length; i++) {
            uint256 result = MathUtils.decPow(bases[i], 0);
            assertEq(result, 1e18);
        }
    }

    // For exponent = 1, returns base, regardless of base
    function testDecPowExponentOne() public {
        uint192[9] memory bases = [
            0,
            1,
            1e18,
            123244254546,
            990000000000000000,
            897890990909098978678609090,
            8789789e27,
            type(uint128).max,
            type(uint192).max
        ];

        for (uint256 i = 0; i < bases.length; i++) {
            uint256 result = MathUtils.decPow(bases[i], 1);
            assertEq(result, bases[i]);
        }
    }

    // For base = 0, returns 0 for any exponent other than 0
    function testDecPowBaseZero() public {
        uint64[10] memory exponents = [1, 3, 17, 44, 118, 1000, 1e6, 1e9, 1e12, 1e18];

        for (uint256 i = 0; i < exponents.length; i++) {
            uint256 result = MathUtils.decPow(0, exponents[i]);
            assertEq(result, 0);
        }
    }

    // For base = 1, returns 1 for any exponent
    function testDecPowBaseOne() public {
        uint64[11] memory exponents = [0, 1, 3, 17, 44, 118, 1000, 1e6, 1e9, 1e12, 1e18];

        for (uint256 i = 0; i < exponents.length; i++) {
            uint256 result = MathUtils.decPow(1e18, exponents[i]);
            assertEq(result, 1e18);
        }
    }

    // For exponent = 2, returns the square of the base
    function testDecPowExponentTwo() public {
        uint80[10] memory bases = [1e18, 1.5e18, 0.5e18, 0.321e18, 4e18, 0.1e18, 0.01e18, 0.99e18, 125.435e18, 99999e18];

        uint96[10] memory expected =
            [1e18, 2.25e18, 0.25e18, 0.103041e18, 16e18, 0.01e18, 0.0001e18, 0.9801e18, 15733.939225e18, 9999800001e18];

        for (uint256 i = 0; i < bases.length; i++) {
            uint256 result = MathUtils.decPow(bases[i], 2);
            assertEq(result, expected[i]);
        }
    }

    // Random tests
    function testDecPowRandom() public {
        uint64[51] memory bases = [
            187706062567632000,
            549137589365708000,
            14163921244333700,
            173482812472018000,
            89043101634399300,
            228676956496486000,
            690422882634616000,
            88730376626724100,
            73384846339964600,
            332854710158557000,
            543415023125456000,
            289299391854347000,
            356290645277924000,
            477806998132950000,
            410750871076822000,
            475222270242414000,
            121455252120304000,
            9639247474367520,
            637853277178133000,
            484746955319000000,
            370594630844984000,
            289829200819417000,
            229325825269870000,
            265776787719080000,
            461409786304156000,
            240236841088914000,
            23036079879643700,
            861616242485528000,
            72241661275119400,
            924071964863292000,
            977575971186712000,
            904200910071210000,
            858551742150349000,
            581850663606974000,
            354836074035232000,
            968639062260900000,
            784478611520428000,
            61314555619941600,
            562295998606858000,
            896709855620154000,
            8484527608110470,
            33987471529490900,
            109333102690035000,
            352436592744656000,
            940730690913636000,
            665800835711181000,
            365267526644046000,
            432669515365048000,
            457498365370101000,
            487046034636363000,
            919877008002166000
        ];

        uint8[51] memory exponents = [
            17,
            2,
            3,
            2,
            2,
            2,
            8,
            11,
            5,
            10,
            24,
            2,
            2,
            8,
            6,
            4,
            22,
            4,
            2,
            6,
            14,
            12,
            8,
            12,
            27,
            11,
            2,
            97,
            212,
            17,
            19,
            15,
            143,
            68,
            16,
            37,
            140,
            13,
            71,
            20,
            111,
            190,
            59,
            4,
            111,
            87,
            208,
            171,
            40,
            12,
            85
        ];

        uint64[51] memory expected = [
            445791,
            301552092054380940,
            2841518643583,
            30096286223201364,
            7928673948673963,
            52293150432495751,
            51632293155573921,
            2684081,
            2128295594269,
            16693487237081,
            439702946262,
            83694138127295015,
            126943023912559468,
            2716564683301052,
            4802539645325781,
            51001992001158415,
            0,
            8633214298,
            406856803206884165,
            12974497294315035,
            921696040698,
            351322263034,
            7649335694527,
            124223733254,
            851811777,
            153828106713,
            530660976221325,
            531430041443,
            0,
            261215237312535195,
            649919912701289852,
            220787304397257033,
            337758087,
            102,
            63160309272,
            307604877091224458,
            1743,
            173,
            2,
            112989701464696907,
            0,
            0,
            0,
            15428509626763407,
            1134095778412648,
            428,
            0,
            0,
            26036,
            178172281758289,
            826094891277892
        ];

        for (uint256 i = 0; i < bases.length; i++) {
            uint256 result = MathUtils.decPow(bases[i], exponents[i]);
            assertEq(result, expected[i]);
        }
    }

    // Does not prematurely decay to zero (exponent = seconds in 1 month)
    function testDecPowNotDecayingToZeroSecondsInOneMonth(uint256 base) public {
        base = bound(base, 0.999995e18, 0.999999999999999999e18);
        uint256 exponent = 30 * 24 * 60 * 60;
        uint256 result = MathUtils.decPow(base, exponent);
        assertGt(result, 0);
    }

    // Does not prematurely decay to zero (exponent = seconds in 3 months)
    function testDecPowNotDecayingToZeroSecondsInThreeMonths(uint256 base) public {
        base = bound(base, 0.999999e18, 0.999999999999e18);
        uint256 exponent = 3 * 30 * 24 * 60 * 60;
        uint256 result = MathUtils.decPow(base, exponent);
        assertGt(result, 0);
    }

    // Does not prematurely decay to zero (exponent = minutes in 1 month)
    function testDecPowNotDecayingToZeroMinutesInOneMonth(uint256 base) public {
        base = bound(base, 0.9997e18, 0.999999999999999999e18);
        uint256 exponent = 30 * 24 * 60;
        uint256 result = MathUtils.decPow(base, exponent);
        assertGt(result, 0);
    }

    // Does not prematurely decay to zero (exponent = minutes in 1-5 years)
    function testDecPowNotDecayingToZeroMinutesInOneFiveYears(uint256 base, uint256 exponent) public {
        uint256 minutesInYear = 365 * 24 * 60;
        base = bound(base, 0.99999e18, 0.999999999999999999e18);
        exponent = bound(exponent, minutesInYear, 5 * minutesInYear);
        uint256 result = MathUtils.decPow(base, exponent);
        assertGt(result, 0);
    }

    // Does not prematurely decay to zero (exponent = minutes in 10 years)
    function testDecPowNotDecayingToZeroMinutesInTenYears(uint256 base) public {
        base = bound(base, 0.999999e18, 0.999999999999999999e18);
        uint256 exponent = 10 * 365 * 24 * 60;
        uint256 result = MathUtils.decPow(base, exponent);
        assertGt(result, 0);
    }

    // Does not prematurely decay to zero (exponent = minutes in 100 years)
    function testDecPowNotDecayingToZeroMinutesInHundredYears(uint256 base) public {
        base = bound(base, 0.9999999e18, 0.999999999999999999e18);
        uint256 exponent = 100 * 365 * 24 * 60;
        uint256 result = MathUtils.decPow(base, exponent);
        assertGt(result, 0);
    }

    // --- computeCR() ---

    // Returns 0 if position's coll is worth 0
    function testComputeCRReturnsZeroForZeroColl() public {
        uint256 price = 0;
        uint256 coll = 1 ether;
        uint256 debt = 100e18;

        assertEq(MathUtils.computeCR(coll, debt, price), 0);
    }

    // Returns 1 for ETH:USD = 100, coll = 1 ETH, debt = 100 R
    function testComputeCRReturnsMaxForMaxColl() public {
        uint256 price = 100e18;
        uint256 coll = 1 ether;
        uint256 debt = 100e18;

        assertEq(MathUtils.computeCR(coll, debt, price), 1e18);
    }

    // Returns correct CR for ETH:USD = 100, coll = 200 ETH, debt = 30 R
    function testComputeCRReturnsCorrectCR1() public {
        uint256 price = 100e18;
        uint256 coll = 200 ether;
        uint256 debt = 30e18;

        assertEq(MathUtils.computeCR(coll, debt, price), 666666666666666666666);
    }

    // Returns correct CR for ETH:USD = 250, coll = 1350 ETH, debt = 127 R
    function testComputeCRReturnsCorrectCR2() public {
        uint256 price = 250e18;
        uint256 coll = 1350 ether;
        uint256 debt = 127e18;

        assertEq(MathUtils.computeCR(coll, debt, price), 2657480314960629921259);
    }

    // Returns correct CR for ETH:USD = 100, coll = 1 ETH, debt = 54321 R
    function testComputeCRReturnsCorrectCR3() public {
        uint256 price = 100e18;
        uint256 coll = 1 ether;
        uint256 debt = 54321e18;

        assertEq(MathUtils.computeCR(coll, debt, price), 1840908672520756);
    }

    // Returns 2^256-1 if position has non-zero coll and zero debt
    function testComputeCRReturnsMaxForZeroDebt() public {
        uint256 price = 100e18;
        uint256 coll = 1 ether;
        uint256 debt = 0;

        assertEq(MathUtils.computeCR(coll, debt, price), type(uint256).max);
    }

    // --- getCompositeDebt() ---

    // Returns composite debt
    function testGetCompositeDebt(uint256 debt) public {
        debt = bound(debt, 0, 10e50);
        assertEq(MathUtils.getCompositeDebt(debt), debt + MathUtils.R_GAS_COMPENSATION);
    }
}
