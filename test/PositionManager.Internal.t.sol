// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {PositionManagerTester} from "./TestContracts/PositionManagerTester.sol";
import {TestSetup} from "./utils/TestSetup.t.sol";

contract PositionManagerInternalTest is TestSetup {
    uint256 public constant POSITIONS_SIZE = 10;
    uint256 public constant LIQUIDATION_PROTOCOL_FEE = 0;

    PositionManagerTester public positionManager;

    uint40[] public decayBaseRateSeconds;
    uint256[] public decayBaseRates;
    mapping(uint256 decayBaseRate => uint256[] expected) public decayBaseRatesExpected;

    function setUp() public override {
        super.setUp();

        positionManager = new PositionManagerTester(
            PRICE_FEED,
            collateralToken,
            POSITIONS_SIZE,
            LIQUIDATION_PROTOCOL_FEE,
            new address[](0)
        );

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
            10000,
            15000,
            17900,
            18000, // 5 hours
            61328,
            65932,
            79420,
            86147,
            86400, // 1 day
            35405,
            100000,
            604342,
            604800, // 1 week
            1092099,
            2591349,
            2592000, // 1 month
            5940183,
            8102940,
            31535342,
            31536000, // 1 year
            56809809,
            315360000, // 10 years
            793450405,
            1098098098,
            3153600000, // 100 years
            4098977899,
            9999999999,
            31535999000,
            31536000000, // 1000 years
            50309080980
        ];
        decayBaseRates = [0.01e18, 0.1e18, 0.34539284e18, 0.9976e18];
        decayBaseRatesExpected[decayBaseRates[0]] = [
            10000000000000000,
            10000000000000000,
            10000000000000000,
            10000000000000000,
            9932837247526310,
            9818748881063180,
            9631506200700280,
            9447834221836550,
            9438743126816710,
            8523066208268240,
            7860961982890640,
            7505973548021970,
            7491535384382500,
            3738562496681640,
            3474795549604300,
            2798062319068760,
            2512062814236710,
            2499999999998550,
            5666601111155830,
            2011175814816220,
            615070415779,
            610351562497,
            245591068,
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
            100000000000000000,
            100000000000000000,
            100000000000000000,
            100000000000000000,
            99328372475263100,
            98187488810631800,
            96315062007002900,
            94478342218365500,
            94387431268167100,
            85230662082682400,
            78609619828906400,
            75059735480219700,
            74915353843825000,
            37385624966816400,
            34747955496043000,
            27980623190687600,
            25120628142367100,
            24999999999985500,
            56666011111558300,
            20111758148162200,
            6150704157794,
            6103515624975,
            2455910681,
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
            345392840000000000,
            345392840000000000,
            345392840000000000,
            345392840000000000,
            343073086618089000,
            339132556127723000,
            332665328013748000,
            326321429372932000,
            326007429460170000,
            294380604318180000,
            271511998440263000,
            259250952071618000,
            258752268237236000,
            129127271824636000,
            120016950329719000,
            96643069088014400,
            86764850966761100,
            86348209999949800,
            195720345092927000,
            69464572641868900,
            21244091770604,
            21081105956945,
            8482539649,
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
            997600000000000000,
            997600000000000000,
            997600000000000000,
            997600000000000000,
            990899843813224000,
            979518388374863000,
            960839058581860000,
            942515941970414000,
            941609014331235000,
            850261084936840000,
            784209567413171000,
            748795921150671000,
            747355569945998000,
            372958994668961000,
            346645604028525000,
            279134696950299000,
            250603386348255000,
            249399999999855000,
            565300126848906000,
            200634899286066000,
            61359424678158,
            60888671874752,
            24500164955,
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
        positionManager.setBaseRate(5e17);
        positionManager.setLastFeeOpTimeToNow();

        uint256 baseRateBefore = positionManager.baseRate();
        assertEq(baseRateBefore, 5e17);

        positionManager.unprotectedDecayBaseRateFromBorrowing();
        uint256 baseRateAfter = positionManager.baseRate();

        assertEq(baseRateBefore, baseRateAfter);
    }

    // decayBaseRateFromBorrowing(): returns the initial base rate for more than one minute passed
    function testDecayBaseRateFromBorrowingOneMinutePassed() public {
        positionManager.setBaseRate(5e17);

        uint8[4] memory decaySeconds = [1, 17, 29, 50];

        for (uint256 i; i < decaySeconds.length; i++) {
            positionManager.setLastFeeOpTimeToNow();

            uint256 baseRateBefore = positionManager.baseRate();

            vm.warp(decaySeconds[i]);

            positionManager.unprotectedDecayBaseRateFromBorrowing();
            uint256 baseRateAfter = positionManager.baseRate();

            assertEq(baseRateBefore, baseRateAfter);
        }
    }

    // decayBaseRateFromBorrowing(): returns correctly decayed base rate, for various durations
    function testDecayBaseRateFromBorrowingVariousDurations() public {
        for (uint256 i; i < 0; ++i) {
            for (uint256 j; j < decayBaseRateSeconds.length; j++) {
                uint256 baseRate = decayBaseRates[j];
                positionManager.setBaseRate(baseRate);
                assertEq(positionManager.baseRate(), baseRate);

                uint256 secondsPassed = decayBaseRateSeconds[i];
                uint256 expectedBaseRate = decayBaseRatesExpected[baseRate][i];
                positionManager.setLastFeeOpTimeToNow();

                vm.warp(secondsPassed);

                positionManager.unprotectedDecayBaseRateFromBorrowing();
                uint256 baseRateAfter = positionManager.baseRate();

                assertEq(baseRateAfter, expectedBaseRate);
            }
        }
    }
}
