// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { PositionManagerTester } from "./mocks/PositionManagerTester.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";

contract PositionManagerInternalTest is TestSetup {
    uint40[] public decayBaseRateSeconds;
    uint256[] public decayBaseRates;
    mapping(uint256 decayBaseRate => uint256[] expected) public decayBaseRatesExpected;

    function setUp() public override {
        super.setUp();

        positionManager = new PositionManagerTester(
            splitLiquidationCollateral
        );
        positionManager.addCollateralToken(collateralToken, PRICE_FEED);

        decayBaseRateSeconds = [
            0,
            1,
            3,
            37,
            432,
            1179,
            2343,
            3547,
            3600, // 1 hour
            10_000,
            15_000,
            17_900,
            18_000, // 5 hours
            61_328,
            65_932,
            79_420,
            86_147,
            86_400, // 1 day
            35_405,
            100_000,
            604_342,
            604_800, // 1 week
            1_092_099,
            2_591_349,
            2_592_000, // 1 month
            5_940_183,
            8_102_940,
            31_535_342,
            31_536_000, // 1 year
            56_809_809,
            315_360_000, // 10 years
            793_450_405,
            1_098_098_098,
            3_153_600_000, // 100 years
            4_098_977_899,
            9_999_999_999,
            31_535_999_000,
            31_536_000_000, // 1000 years
            50_309_080_980
        ];
        decayBaseRates = [0.01e18, 0.1e18, 0.34539284e18, 0.9976e18];
        decayBaseRatesExpected[decayBaseRates[0]] = [
            10_000_000_000_000_000,
            10_000_000_000_000_000,
            10_000_000_000_000_000,
            10_000_000_000_000_000,
            9_932_837_247_526_310,
            9_818_748_881_063_180,
            9_631_506_200_700_280,
            9_447_834_221_836_550,
            9_438_743_126_816_710,
            8_523_066_208_268_240,
            7_860_961_982_890_640,
            7_505_973_548_021_970,
            7_491_535_384_382_500,
            3_738_562_496_681_640,
            3_474_795_549_604_300,
            2_798_062_319_068_760,
            2_512_062_814_236_710,
            2_499_999_999_998_550,
            5_666_601_111_155_830,
            2_011_175_814_816_220,
            615_070_415_779,
            610_351_562_497,
            245_591_068,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        ];
        decayBaseRatesExpected[decayBaseRates[1]] = [
            100_000_000_000_000_000,
            100_000_000_000_000_000,
            100_000_000_000_000_000,
            100_000_000_000_000_000,
            99_328_372_475_263_100,
            98_187_488_810_631_800,
            96_315_062_007_002_900,
            94_478_342_218_365_500,
            94_387_431_268_167_100,
            85_230_662_082_682_400,
            78_609_619_828_906_400,
            75_059_735_480_219_700,
            74_915_353_843_825_000,
            37_385_624_966_816_400,
            34_747_955_496_043_000,
            27_980_623_190_687_600,
            25_120_628_142_367_100,
            24_999_999_999_985_500,
            56_666_011_111_558_300,
            20_111_758_148_162_200,
            6_150_704_157_794,
            6_103_515_624_975,
            2_455_910_681,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        ];
        decayBaseRatesExpected[decayBaseRates[2]] = [
            345_392_840_000_000_000,
            345_392_840_000_000_000,
            345_392_840_000_000_000,
            345_392_840_000_000_000,
            343_073_086_618_089_000,
            339_132_556_127_723_000,
            332_665_328_013_748_000,
            326_321_429_372_932_000,
            326_007_429_460_170_000,
            294_380_604_318_180_000,
            271_511_998_440_263_000,
            259_250_952_071_618_000,
            258_752_268_237_236_000,
            129_127_271_824_636_000,
            120_016_950_329_719_000,
            96_643_069_088_014_400,
            86_764_850_966_761_100,
            86_348_209_999_949_800,
            195_720_345_092_927_000,
            69_464_572_641_868_900,
            21_244_091_770_604,
            21_081_105_956_945,
            8_482_539_649,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        ];
        decayBaseRatesExpected[decayBaseRates[3]] = [
            997_600_000_000_000_000,
            997_600_000_000_000_000,
            997_600_000_000_000_000,
            997_600_000_000_000_000,
            990_899_843_813_224_000,
            979_518_388_374_863_000,
            960_839_058_581_860_000,
            942_515_941_970_414_000,
            941_609_014_331_235_000,
            850_261_084_936_840_000,
            784_209_567_413_171_000,
            748_795_921_150_671_000,
            747_355_569_945_998_000,
            372_958_994_668_961_000,
            346_645_604_028_525_000,
            279_134_696_950_299_000,
            250_603_386_348_255_000,
            249_399_999_999_855_000,
            565_300_126_848_906_000,
            200_634_899_286_066_000,
            61_359_424_678_158,
            60_888_671_874_752,
            24_500_164_955,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        ];
    }

    // decayBaseRateFromBorrowing(): returns the initial base rate for no time increase
    function testDecayBaseRateFromBorrowingNoTimeIncrease() public {
        PositionManagerTester(address(positionManager)).setBaseRate(5e17);
        PositionManagerTester(address(positionManager)).setLastFeeOpTimeToNow();

        uint256 baseRateBefore = positionManager.baseRate();
        assertEq(baseRateBefore, 5e17);

        PositionManagerTester(address(positionManager)).unprotectedDecayBaseRateFromBorrowing();
        uint256 baseRateAfter = positionManager.baseRate();

        assertEq(baseRateBefore, baseRateAfter);
    }

    // decayBaseRateFromBorrowing(): returns the initial base rate for more than one minute passed
    function testDecayBaseRateFromBorrowingOneMinutePassed() public {
        PositionManagerTester(address(positionManager)).setBaseRate(5e17);

        uint8[4] memory decaySeconds = [1, 17, 29, 50];

        for (uint256 i; i < decaySeconds.length; i++) {
            PositionManagerTester(address(positionManager)).setLastFeeOpTimeToNow();

            uint256 baseRateBefore = positionManager.baseRate();

            vm.warp(decaySeconds[i]);

            PositionManagerTester(address(positionManager)).unprotectedDecayBaseRateFromBorrowing();
            uint256 baseRateAfter = positionManager.baseRate();

            assertEq(baseRateBefore, baseRateAfter);
        }
    }

    // decayBaseRateFromBorrowing(): returns correctly decayed base rate, for various durations
    function testDecayBaseRateFromBorrowingVariousDurations() public {
        for (uint256 i; i < 0; ++i) {
            for (uint256 j; j < decayBaseRateSeconds.length; j++) {
                uint256 baseRate = decayBaseRates[j];
                PositionManagerTester(address(positionManager)).setBaseRate(baseRate);
                assertEq(positionManager.baseRate(), baseRate);

                uint256 secondsPassed = decayBaseRateSeconds[i];
                uint256 expectedBaseRate = decayBaseRatesExpected[baseRate][i];
                PositionManagerTester(address(positionManager)).setLastFeeOpTimeToNow();

                vm.warp(secondsPassed);

                PositionManagerTester(address(positionManager)).unprotectedDecayBaseRateFromBorrowing();
                uint256 baseRateAfter = positionManager.baseRate();

                assertEq(baseRateAfter, expectedBaseRate);
            }
        }
    }
}
