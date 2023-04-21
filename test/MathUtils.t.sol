// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";

contract MathUtilsTest is Test {
    // --- _decPow() ---

    // For exponent = 0, returns 1, regardless of base
    function testDecPowExponentZero() public {
        uint120[7] memory bases =
            [0, 1, 1e18, 123_244_254_546, 990_000_000_000_000_000, 897_890_990_909_098_978_678_609_090, 8_789_789e27];

        for (uint256 i = 0; i < bases.length; i++) {
            uint256 result = MathUtils._decPow(bases[i], 0);
            assertEq(result, 1e18);
        }
    }

    // For exponent = 1, returns base, regardless of base
    function testDecPowExponentOne() public {
        uint192[9] memory bases = [
            0,
            1,
            1e18,
            123_244_254_546,
            990_000_000_000_000_000,
            897_890_990_909_098_978_678_609_090,
            8_789_789e27,
            type(uint128).max,
            type(uint192).max
        ];

        for (uint256 i = 0; i < bases.length; i++) {
            uint256 result = MathUtils._decPow(bases[i], 1);
            assertEq(result, bases[i]);
        }
    }

    // For base = 0, returns 0 for any exponent other than 0
    function testDecPowBaseZero() public {
        uint64[10] memory exponents = [1, 3, 17, 44, 118, 1000, 1e6, 1e9, 1e12, 1e18];

        for (uint256 i = 0; i < exponents.length; i++) {
            uint256 result = MathUtils._decPow(0, exponents[i]);
            assertEq(result, 0);
        }
    }

    // For base = 1, returns 1 for any exponent
    function testDecPowBaseOne() public {
        uint64[11] memory exponents = [0, 1, 3, 17, 44, 118, 1000, 1e6, 1e9, 1e12, 1e18];

        for (uint256 i = 0; i < exponents.length; i++) {
            uint256 result = MathUtils._decPow(1e18, exponents[i]);
            assertEq(result, 1e18);
        }
    }

    // For exponent = 2, returns the square of the base
    function testDecPowExponentTwo() public {
        uint80[10] memory bases = [1e18, 1.5e18, 0.5e18, 0.321e18, 4e18, 1e17, 0.01e18, 0.99e18, 125.435e18, 99_999e18];

        uint96[10] memory expected = [
            1e18,
            2.25e18,
            0.25e18,
            0.103041e18,
            16e18,
            0.01e18,
            0.0001e18,
            0.9801e18,
            15_733.939225e18,
            9_999_800_001e18
        ];

        for (uint256 i = 0; i < bases.length; i++) {
            uint256 result = MathUtils._decPow(bases[i], 2);
            assertEq(result, expected[i]);
        }
    }

    // Random tests
    function testDecPowRandom() public {
        uint64[51] memory bases = [
            187_706_062_567_632_000,
            549_137_589_365_708_000,
            14_163_921_244_333_700,
            173_482_812_472_018_000,
            89_043_101_634_399_300,
            228_676_956_496_486_000,
            690_422_882_634_616_000,
            88_730_376_626_724_100,
            73_384_846_339_964_600,
            332_854_710_158_557_000,
            543_415_023_125_456_000,
            289_299_391_854_347_000,
            356_290_645_277_924_000,
            477_806_998_132_950_000,
            410_750_871_076_822_000,
            475_222_270_242_414_000,
            121_455_252_120_304_000,
            9_639_247_474_367_520,
            637_853_277_178_133_000,
            484_746_955_319_000_000,
            370_594_630_844_984_000,
            289_829_200_819_417_000,
            229_325_825_269_870_000,
            265_776_787_719_080_000,
            461_409_786_304_156_000,
            240_236_841_088_914_000,
            23_036_079_879_643_700,
            861_616_242_485_528_000,
            72_241_661_275_119_400,
            924_071_964_863_292_000,
            977_575_971_186_712_000,
            904_200_910_071_210_000,
            858_551_742_150_349_000,
            581_850_663_606_974_000,
            354_836_074_035_232_000,
            968_639_062_260_900_000,
            784_478_611_520_428_000,
            61_314_555_619_941_600,
            562_295_998_606_858_000,
            896_709_855_620_154_000,
            8_484_527_608_110_470,
            33_987_471_529_490_900,
            109_333_102_690_035_000,
            352_436_592_744_656_000,
            940_730_690_913_636_000,
            665_800_835_711_181_000,
            365_267_526_644_046_000,
            432_669_515_365_048_000,
            457_498_365_370_101_000,
            487_046_034_636_363_000,
            919_877_008_002_166_000
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
            445_791,
            301_552_092_054_380_940,
            2_841_518_643_583,
            30_096_286_223_201_364,
            7_928_673_948_673_963,
            52_293_150_432_495_751,
            51_632_293_155_573_921,
            2_684_081,
            2_128_295_594_269,
            16_693_487_237_081,
            439_702_946_262,
            83_694_138_127_295_015,
            126_943_023_912_559_468,
            2_716_564_683_301_052,
            4_802_539_645_325_781,
            51_001_992_001_158_415,
            0,
            8_633_214_298,
            406_856_803_206_884_165,
            12_974_497_294_315_035,
            921_696_040_698,
            351_322_263_034,
            7_649_335_694_527,
            124_223_733_254,
            851_811_777,
            153_828_106_713,
            530_660_976_221_325,
            531_430_041_443,
            0,
            261_215_237_312_535_195,
            649_919_912_701_289_852,
            220_787_304_397_257_033,
            337_758_087,
            102,
            63_160_309_272,
            307_604_877_091_224_458,
            1743,
            173,
            2,
            112_989_701_464_696_907,
            0,
            0,
            0,
            15_428_509_626_763_407,
            1_134_095_778_412_648,
            428,
            0,
            0,
            26_036,
            178_172_281_758_289,
            826_094_891_277_892
        ];

        for (uint256 i = 0; i < bases.length; i++) {
            uint256 result = MathUtils._decPow(bases[i], exponents[i]);
            assertEq(result, expected[i]);
        }
    }

    // Does not prematurely decay to zero (exponent = seconds in 1 month)
    function testDecPowNotDecayingToZeroSecondsInOneMonth(uint256 base) public {
        base = bound(base, 0.999995e18, 0.999999999999999999e18);
        uint256 exponent = 30 * 24 * 60 * 60;
        uint256 result = MathUtils._decPow(base, exponent);
        assertGt(result, 0);
    }

    // Does not prematurely decay to zero (exponent = seconds in 3 months)
    function testDecPowNotDecayingToZeroSecondsInThreeMonths(uint256 base) public {
        base = bound(base, 0.999999e18, 0.999999999999e18);
        uint256 exponent = 3 * 30 * 24 * 60 * 60;
        uint256 result = MathUtils._decPow(base, exponent);
        assertGt(result, 0);
    }

    // Does not prematurely decay to zero (exponent = minutes in 1 month)
    function testDecPowNotDecayingToZeroMinutesInOneMonth(uint256 base) public {
        base = bound(base, 0.9997e18, 0.999999999999999999e18);
        uint256 exponent = 30 * 24 * 60;
        uint256 result = MathUtils._decPow(base, exponent);
        assertGt(result, 0);
    }

    // Does not prematurely decay to zero (exponent = minutes in 1-5 years)
    function testDecPowNotDecayingToZeroMinutesInOneFiveYears(uint256 base, uint256 exponent) public {
        uint256 minutesInYear = 365 * 24 * 60;
        base = bound(base, 0.99999e18, 0.999999999999999999e18);
        exponent = bound(exponent, minutesInYear, 5 * minutesInYear);
        uint256 result = MathUtils._decPow(base, exponent);
        assertGt(result, 0);
    }

    // Does not prematurely decay to zero (exponent = minutes in 10 years)
    function testDecPowNotDecayingToZeroMinutesInTenYears(uint256 base) public {
        base = bound(base, 0.999999e18, 0.999999999999999999e18);
        uint256 exponent = 10 * 365 * 24 * 60;
        uint256 result = MathUtils._decPow(base, exponent);
        assertGt(result, 0);
    }

    // Does not prematurely decay to zero (exponent = minutes in 100 years)
    function testDecPowNotDecayingToZeroMinutesInHundredYears(uint256 base) public {
        base = bound(base, 0.9999999e18, 0.999999999999999999e18);
        uint256 exponent = 100 * 365 * 24 * 60;
        uint256 result = MathUtils._decPow(base, exponent);
        assertGt(result, 0);
    }

    // --- _computeCR() ---

    // Returns 0 if position's collateral is worth 0
    function test_computeCRReturnsZeroForZeroCollateral() public {
        uint256 price = 0;
        uint256 collateral = 1 ether;
        uint256 debt = 100e18;

        assertEq(MathUtils._computeCR(collateral, debt, price), 0);
    }

    // Returns 1 for ETH:USD = 100, collateral = 1 ETH, debt = 100 R
    function test_computeCRReturnsMaxForMaxCollateral() public {
        uint256 price = 100e18;
        uint256 collateral = 1 ether;
        uint256 debt = 100e18;

        assertEq(MathUtils._computeCR(collateral, debt, price), 1e18);
    }

    // Returns correct CR for ETH:USD = 100, collateral = 200 ETH, debt = 30 R
    function test_computeCRReturnsCorrectCR1() public {
        uint256 price = 100e18;
        uint256 collateral = 200 ether;
        uint256 debt = 30e18;

        assertEq(MathUtils._computeCR(collateral, debt, price), 666_666_666_666_666_666_666);
    }

    // Returns correct CR for ETH:USD = 250, collateral = 1350 ETH, debt = 127 R
    function test_computeCRReturnsCorrectCR2() public {
        uint256 price = 250e18;
        uint256 collateral = 1350 ether;
        uint256 debt = 127e18;

        assertEq(MathUtils._computeCR(collateral, debt, price), 2_657_480_314_960_629_921_259);
    }

    // Returns correct CR for ETH:USD = 100, collateral = 1 ETH, debt = 54321 R
    function test_computeCRReturnsCorrectCR3() public {
        uint256 price = 100e18;
        uint256 collateral = 1 ether;
        uint256 debt = 54_321e18;

        assertEq(MathUtils._computeCR(collateral, debt, price), 1_840_908_672_520_756);
    }

    // Returns 2^256-1 if position has non-zero collateral and zero debt
    function test_computeCRReturnsMaxForZeroDebt() public {
        uint256 price = 100e18;
        uint256 collateral = 1 ether;
        uint256 debt = 0;

        assertEq(MathUtils._computeCR(collateral, debt, price), type(uint256).max);
    }
}
