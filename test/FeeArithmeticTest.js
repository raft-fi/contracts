const Decimal = require("decimal.js");
const deploymentHelper = require("../utils/deploymentHelpers.js")
const { BNConverter } = require("../utils/BNConverter.js")
const testHelpers = require("../utils/testHelpers.js")
const MathUtilsTester = artifacts.require("./MathUtilsTester.sol")

const th = testHelpers.TestHelper
const timeValues = testHelpers.TimeValues
const dec = th.dec
const toBN = th.toBN
const getDifference = th.getDifference

contract('Fee arithmetic tests', async accounts => {
  let contracts
  let positionManagerTester
  let mathTester

  const [owner] = accounts

  /* Object holds arrays for seconds passed, and the corresponding expected decayed base rate, given an initial
  base rate */

  const decayBaseRateResults = {
    'seconds': [
      0,
      1,
      3,
      37,
      432,
      1179,
      2343,
      3547,
      3600,	 // 1 hour
      10000,
      15000,
      17900,
      18000,	  // 5 hours
      61328,
      65932,
      79420,
      86147,
      86400,	  // 1 day
      35405,
      100000,
      604342,
      604800,	  // 1 week
      1092099,
      2591349,
      2592000,	  // 1 month
      5940183,
      8102940,
      31535342,
      31536000, // 1 year
      56809809,
      315360000,	  // 10 years
      793450405,
      1098098098,
      3153600000,	  // 100 years
      4098977899,
      9999999999,
      31535999000,
      31536000000,	 // 1000 years
      50309080980,
    ],
    '0.01': [
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
      0,
    ],
    '0.1': [
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
      0,
    ],
    '0.34539284': [
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
      0,
    ],
    '0.9976': [
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
      0,
    ]
  }

  before(async () => {
    mathTester = await MathUtilsTester.new()
    MathUtilsTester.setAsDeployed(mathTester)
  })

  beforeEach(async () => {
    contracts = await deploymentHelper.deployLiquityCore(owner)
    positionManagerTester = contracts.positionManager
  })

  it("decayBaseRateFromBorrowing(): returns the initial base rate for no time increase", async () => {
    await positionManagerTester.setBaseRate(dec(5, 17))
    await positionManagerTester.setLastFeeOpTimeToNow()

    const baseRateBefore = await positionManagerTester.baseRate()
    assert.equal(baseRateBefore, dec(5, 17))

    await positionManagerTester.unprotectedDecayBaseRateFromBorrowing()
    const baseRateAfter = await positionManagerTester.baseRate()

    assert.isTrue(baseRateBefore.eq(baseRateAfter))
  })

  it("decayBaseRateFromBorrowing(): returns the initial base rate for less than one minute passed ", async () => {
    await positionManagerTester.setBaseRate(dec(5, 17))
    await positionManagerTester.setLastFeeOpTimeToNow()

    // 1 second
    const baseRateBefore_1 = await positionManagerTester.baseRate()
    assert.equal(baseRateBefore_1, dec(5, 17))

    await th.fastForwardTime(1, web3.currentProvider)

    await positionManagerTester.unprotectedDecayBaseRateFromBorrowing()
    const baseRateAfter_1 = await positionManagerTester.baseRate()

    assert.isTrue(baseRateBefore_1.eq(baseRateAfter_1))

    // 17 seconds
    await positionManagerTester.setLastFeeOpTimeToNow()

    const baseRateBefore_2 = await positionManagerTester.baseRate()
    await th.fastForwardTime(17, web3.currentProvider)

    await positionManagerTester.unprotectedDecayBaseRateFromBorrowing()
    const baseRateAfter_2 = await positionManagerTester.baseRate()

    assert.isTrue(baseRateBefore_2.eq(baseRateAfter_2))

    // 29 seconds
    await positionManagerTester.setLastFeeOpTimeToNow()

    const baseRateBefore_3 = await positionManagerTester.baseRate()
    await th.fastForwardTime(29, web3.currentProvider)

    await positionManagerTester.unprotectedDecayBaseRateFromBorrowing()
    const baseRateAfter_3 = await positionManagerTester.baseRate()

    assert.isTrue(baseRateBefore_3.eq(baseRateAfter_3))

    // 50 seconds
    await positionManagerTester.setLastFeeOpTimeToNow()

    const baseRateBefore_4 = await positionManagerTester.baseRate()
    await th.fastForwardTime(50, web3.currentProvider)

    await positionManagerTester.unprotectedDecayBaseRateFromBorrowing()
    const baseRateAfter_4 = await positionManagerTester.baseRate()

    assert.isTrue(baseRateBefore_4.eq(baseRateAfter_4))

    // (cant quite test up to 59 seconds, as execution of the final tx takes >1 second before the block is mined)
  })

  it("decayBaseRateFromBorrowing(): returns correctly decayed base rate, for various durations. Initial baseRate = 0.01", async () => {
    // baseRate = 0.01
    for (i = 0; i < decayBaseRateResults.seconds.length; i++) {
      // Set base rate to 0.01 in PositionManager
      await positionManagerTester.setBaseRate(dec(1, 16))
      const contractBaseRate = await positionManagerTester.baseRate()
      assert.equal(contractBaseRate, dec(1, 16))

      const startBaseRate = '0.01'

      const secondsPassed = decayBaseRateResults.seconds[i]
      const expectedDecayedBaseRate = decayBaseRateResults[startBaseRate][i]
      await positionManagerTester.setLastFeeOpTimeToNow()

      // Progress time
      await th.fastForwardTime(secondsPassed, web3.currentProvider)

      await positionManagerTester.unprotectedDecayBaseRateFromBorrowing()
      const decayedBaseRate = await positionManagerTester.baseRate()

      assert.isAtMost(getDifference(expectedDecayedBaseRate.toString(), decayedBaseRate.toString()), 100000) // allow absolute error tolerance of 1e-13
    }
  })

  it("decayBaseRateFromBorrowing(): returns correctly decayed base rate, for various durations. Initial baseRate = 0.1", async () => {
    // baseRate = 0.1
    for (i = 0; i < decayBaseRateResults.seconds.length; i++) {
      // Set base rate to 0.1 in PositionManager
      await positionManagerTester.setBaseRate(dec(1, 17))
      const contractBaseRate = await positionManagerTester.baseRate()
      assert.equal(contractBaseRate, dec(1, 17))

      const secondsPassed = decayBaseRateResults.seconds[i]
      const expectedDecayedBaseRate = decayBaseRateResults['0.1'][i]
      await positionManagerTester.setLastFeeOpTimeToNow()

      // Progress time
      await th.fastForwardTime(secondsPassed, web3.currentProvider)

      await positionManagerTester.unprotectedDecayBaseRateFromBorrowing()
      const decayedBaseRate = await positionManagerTester.baseRate()

      assert.isAtMost(getDifference(expectedDecayedBaseRate.toString(), decayedBaseRate.toString()), 1000000) // allow absolute error tolerance of 1e-12
    }
  })

  it("decayBaseRateFromBorrowing(): returns correctly decayed base rate, for various durations. Initial baseRate = 0.34539284", async () => {
    // baseRate = 0.34539284
    for (i = 0; i < decayBaseRateResults.seconds.length; i++) {
      // Set base rate to 0.1 in PositionManager
      await positionManagerTester.setBaseRate('345392840000000000')
      const contractBaseRate = await positionManagerTester.baseRate()
      await positionManagerTester.setBaseRate('345392840000000000')

      const startBaseRate = '0.34539284'

      const secondsPassed = decayBaseRateResults.seconds[i]
      const expectedDecayedBaseRate = decayBaseRateResults[startBaseRate][i]
      await positionManagerTester.setLastFeeOpTimeToNow()

      // Progress time
      await th.fastForwardTime(secondsPassed, web3.currentProvider)

      await positionManagerTester.unprotectedDecayBaseRateFromBorrowing()
      const decayedBaseRate = await positionManagerTester.baseRate()

      assert.isAtMost(getDifference(expectedDecayedBaseRate.toString(), decayedBaseRate.toString()), 1000000) // allow absolute error tolerance of 1e-12
    }
  })

  it("decayBaseRateFromBorrowing(): returns correctly decayed base rate, for various durations. Initial baseRate = 0.9976", async () => {
    // baseRate = 0.9976
    for (i = 0; i < decayBaseRateResults.seconds.length; i++) {
      // Set base rate to 0.9976 in PositionManager
      await positionManagerTester.setBaseRate('997600000000000000')
      await positionManagerTester.setBaseRate('997600000000000000')

      const startBaseRate = '0.9976'

      const secondsPassed = decayBaseRateResults.seconds[i]
      const expectedDecayedBaseRate = decayBaseRateResults[startBaseRate][i]
      await positionManagerTester.setLastFeeOpTimeToNow()

      // progress time
      await th.fastForwardTime(secondsPassed, web3.currentProvider)

      await positionManagerTester.unprotectedDecayBaseRateFromBorrowing()
      const decayedBaseRate = await positionManagerTester.baseRate()

      assert.isAtMost(getDifference(expectedDecayedBaseRate.toString(), decayedBaseRate.toString()), 10000000) // allow absolute error tolerance of 1e-11
    }
  })
})
