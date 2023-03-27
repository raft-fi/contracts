const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")
const TroveManagerTester = artifacts.require("./TroveManagerTester.sol")
const BorrowerOperationsTester = artifacts.require("./BorrowerOperationsTester.sol")
const LUSDToken = artifacts.require("LUSDToken")

const th = testHelpers.TestHelper
const dec = th.dec
const toBN = th.toBN
const mv = testHelpers.MoneyValues

const GAS_PRICE = 10000000

/// TODO: fix skipped tests as part of https://github.com/tempusfinance/raft/issues/14
contract('Gas compensation tests', async accounts => {
  const [
    owner, liquidator,
    alice, bob, carol, dennis, erin, flyn, harriet,
    whale] = accounts;

  let priceFeed
  let lusdToken
  let troveManager
  let activePool
  let defaultPool
  let wstETHTokenMock

  let contracts
  let troveManagerTester
  let borrowerOperationsTester

  const openTrove = async (params) => th.openTrove(contracts, params)

  const logICRs = (ICRList) => {
    for (let i = 0; i < ICRList.length; i++) {
      console.log(`account: ${i + 1} ICR: ${ICRList[i].toString()}`)
    }
  }

  before(async () => {
    troveManagerTester = await TroveManagerTester.new()
    borrowerOperationsTester = await BorrowerOperationsTester.new()

    TroveManagerTester.setAsDeployed(troveManagerTester)
    BorrowerOperationsTester.setAsDeployed(borrowerOperationsTester)
  })

  beforeEach(async () => {
    contracts = await deploymentHelper.deployLiquityCore()
    contracts.troveManager = await TroveManagerTester.new()
    contracts.lusdToken = await LUSDToken.new(
      contracts.troveManager.address,
      contracts.borrowerOperations.address
    )

    await th.fillAccountsWithWstETH(contracts, [
      owner, liquidator,
      alice, bob, carol, dennis, erin, flyn, harriet,
      whale,
    ])

    priceFeed = contracts.priceFeedTestnet
    lusdToken = contracts.lusdToken
    sortedTroves = contracts.sortedTroves
    troveManager = contracts.troveManager
    activePool = contracts.activePool
    defaultPool = contracts.defaultPool
    borrowerOperations = contracts.borrowerOperations
    wstETHTokenMock = contracts.wstETHTokenMock

    await deploymentHelper.connectCoreContracts(contracts, owner)
  })

  // --- Raw gas compensation calculations ---

  it('_getCollGasCompensation(): returns the 0.5% of collaterall if it is < $10 in value', async () => {
    /*
    ETH:USD price = 1
    coll = 1 ETH: $1 in value
    -> Expect 0.5% of collaterall as gas compensation */
    await priceFeed.setPrice(dec(1, 18))
    // const price_1 = await priceFeed.getPrice()
    const gasCompensation_1 = (await troveManagerTester.getCollGasCompensation(dec(1, 'ether'))).toString()
    assert.equal(gasCompensation_1, dec(5, 15))

    /*
    ETH:USD price = 28.4
    coll = 0.1 ETH: $2.84 in value
    -> Expect 0.5% of collaterall as gas compensation */
    await priceFeed.setPrice('28400000000000000000')
    // const price_2 = await priceFeed.getPrice()
    const gasCompensation_2 = (await troveManagerTester.getCollGasCompensation(dec(100, 'finney'))).toString()
    assert.equal(gasCompensation_2, dec(5, 14))

    /*
    ETH:USD price = 1000000000 (1 billion)
    coll = 0.000000005 ETH (5e9 wei): $5 in value
    -> Expect 0.5% of collaterall as gas compensation */
    await priceFeed.setPrice(dec(1, 27))
    // const price_3 = await priceFeed.getPrice()
    const gasCompensation_3 = (await troveManagerTester.getCollGasCompensation('5000000000')).toString()
    assert.equal(gasCompensation_3, '25000000')
  })

  it('_getCollGasCompensation(): returns 0.5% of collaterall when 0.5% of collateral < $10 in value', async () => {
    const price = await priceFeed.getPrice()
    assert.equal(price, dec(200, 18))

    /*
    ETH:USD price = 200
    coll = 9.999 ETH
    0.5% of coll = 0.04995 ETH. USD value: $9.99
    -> Expect 0.5% of collaterall as gas compensation */
    const gasCompensation_1 = (await troveManagerTester.getCollGasCompensation('9999000000000000000')).toString()
    assert.equal(gasCompensation_1, '49995000000000000')

    /* ETH:USD price = 200
     coll = 0.055 ETH
     0.5% of coll = 0.000275 ETH. USD value: $0.055
     -> Expect 0.5% of collaterall as gas compensation */
    const gasCompensation_2 = (await troveManagerTester.getCollGasCompensation('55000000000000000')).toString()
    assert.equal(gasCompensation_2, dec(275, 12))

    /* ETH:USD price = 200
    coll = 6.09232408808723580 ETH
    0.5% of coll = 0.004995 ETH. USD value: $6.09
    -> Expect 0.5% of collaterall as gas compensation */
    const gasCompensation_3 = (await troveManagerTester.getCollGasCompensation('6092324088087235800')).toString()
    assert.equal(gasCompensation_3, '30461620440436179')
  })

  it('getCollGasCompensation(): returns 0.5% of collaterall when 0.5% of collateral = $10 in value', async () => {
    const price = await priceFeed.getPrice()
    assert.equal(price, dec(200, 18))

    /*
    ETH:USD price = 200
    coll = 10 ETH
    0.5% of coll = 0.5 ETH. USD value: $10
    -> Expect 0.5% of collaterall as gas compensation */
    const gasCompensation = (await troveManagerTester.getCollGasCompensation(dec(10, 'ether'))).toString()
    assert.equal(gasCompensation, '50000000000000000')
  })

  it('getCollGasCompensation(): returns 0.5% of collaterall when 0.5% of collateral = $10 in value', async () => {
    const price = await priceFeed.getPrice()
    assert.equal(price, dec(200, 18))

    /*
    ETH:USD price = 200 $/E
    coll = 100 ETH
    0.5% of coll = 0.5 ETH. USD value: $100
    -> Expect $100 gas compensation, i.e. 0.5 ETH */
    const gasCompensation_1 = (await troveManagerTester.getCollGasCompensation(dec(100, 'ether'))).toString()
    assert.equal(gasCompensation_1, dec(500, 'finney'))

    /*
    ETH:USD price = 200 $/E
    coll = 10.001 ETH
    0.5% of coll = 0.050005 ETH. USD value: $10.001
    -> Expect $100 gas compensation, i.e.  0.050005  ETH */
    const gasCompensation_2 = (await troveManagerTester.getCollGasCompensation('10001000000000000000')).toString()
    assert.equal(gasCompensation_2, '50005000000000000')

    /*
    ETH:USD price = 200 $/E
    coll = 37.5 ETH
    0.5% of coll = 0.1875 ETH. USD value: $37.5
    -> Expect $37.5 gas compensation i.e.  0.1875  ETH */
    const gasCompensation_3 = (await troveManagerTester.getCollGasCompensation('37500000000000000000')).toString()
    assert.equal(gasCompensation_3, '187500000000000000')

    /*
    ETH:USD price = 45323.54542 $/E
    coll = 94758.230582309850 ETH
    0.5% of coll = 473.7911529 ETH. USD value: $21473894.84
    -> Expect $21473894.8385808 gas compensation, i.e.  473.7911529115490  ETH */
    await priceFeed.setPrice('45323545420000000000000')
    const gasCompensation_4 = await troveManagerTester.getCollGasCompensation('94758230582309850000000')
    assert.isAtMost(th.getDifference(gasCompensation_4, '473791152911549000000'), 1000000)

    /*
    ETH:USD price = 1000000 $/E (1 million)
    coll = 300000000 ETH   (300 million)
    0.5% of coll = 1500000 ETH. USD value: $150000000000
    -> Expect $150000000000 gas compensation, i.e. 1500000 ETH */
    await priceFeed.setPrice(dec(1, 24))
    const price_2 = await priceFeed.getPrice()
    const gasCompensation_5 = (await troveManagerTester.getCollGasCompensation('300000000000000000000000000')).toString()
    assert.equal(gasCompensation_5, '1500000000000000000000000')
  })

  // --- Composite debt calculations ---

  // gets debt + 50 when 0.5% of coll < $10
  it('_getCompositeDebt(): returns (debt + 50) when collateral < $10 in value', async () => {
    const price = await priceFeed.getPrice()
    assert.equal(price, dec(200, 18))

    /*
    ETH:USD price = 200
    coll = 9.999 ETH
    debt = 10 LUSD
    0.5% of coll = 0.04995 ETH. USD value: $9.99
    -> Expect composite debt = 10 + 200  = 2100 LUSD*/
    const compositeDebt_1 = await troveManagerTester.getCompositeDebt(dec(10, 18))
    assert.equal(compositeDebt_1, dec(210, 18))

    /* ETH:USD price = 200
     coll = 0.055 ETH
     debt = 0 LUSD
     0.5% of coll = 0.000275 ETH. USD value: $0.055
     -> Expect composite debt = 0 + 200 = 200 LUSD*/
    const compositeDebt_2 = await troveManagerTester.getCompositeDebt(0)
    assert.equal(compositeDebt_2, dec(200, 18))

    // /* ETH:USD price = 200
    // coll = 6.09232408808723580 ETH
    // debt = 200 LUSD
    // 0.5% of coll = 0.004995 ETH. USD value: $6.09
    // -> Expect  composite debt =  200 + 200 = 400  LUSD */
    const compositeDebt_3 = await troveManagerTester.getCompositeDebt(dec(200, 18))
    assert.equal(compositeDebt_3, '400000000000000000000')
  })

  // returns $10 worth of ETH when 0.5% of coll == $10
  it('getCompositeDebt(): returns (debt + 50) collateral = $10 in value', async () => {
    const price = await priceFeed.getPrice()
    assert.equal(price, dec(200, 18))

    /*
    ETH:USD price = 200
    coll = 10 ETH
    debt = 123.45 LUSD
    0.5% of coll = 0.5 ETH. USD value: $10
    -> Expect composite debt = (123.45 + 200) = 323.45 LUSD  */
    const compositeDebt = await troveManagerTester.getCompositeDebt('123450000000000000000')
    assert.equal(compositeDebt, '323450000000000000000')
  })

  /// ***

  // gets debt + 50 when 0.5% of coll > 10
  it('getCompositeDebt(): returns (debt + 50) when 0.5% of collateral > $10 in value', async () => {
    const price = await priceFeed.getPrice()
    assert.equal(price, dec(200, 18))

    /*
    ETH:USD price = 200 $/E
    coll = 100 ETH
    debt = 2000 LUSD
    -> Expect composite debt = (2000 + 200) = 2200 LUSD  */
    const compositeDebt_1 = (await troveManagerTester.getCompositeDebt(dec(2000, 18))).toString()
    assert.equal(compositeDebt_1, '2200000000000000000000')

    /*
    ETH:USD price = 200 $/E
    coll = 10.001 ETH
    debt = 200 LUSD
    -> Expect composite debt = (200 + 200) = 400 LUSD  */
    const compositeDebt_2 = (await troveManagerTester.getCompositeDebt(dec(200, 18))).toString()
    assert.equal(compositeDebt_2, '400000000000000000000')

    /*
    ETH:USD price = 200 $/E
    coll = 37.5 ETH
    debt = 500 LUSD
    -> Expect composite debt = (500 + 200) = 700 LUSD  */
    const compositeDebt_3 = (await troveManagerTester.getCompositeDebt(dec(500, 18))).toString()
    assert.equal(compositeDebt_3, '700000000000000000000')

    /*
    ETH:USD price = 45323.54542 $/E
    coll = 94758.230582309850 ETH
    debt = 1 billion LUSD
    -> Expect composite debt = (1000000000 + 200) = 1000000200 LUSD  */
    await priceFeed.setPrice('45323545420000000000000')
    const price_2 = await priceFeed.getPrice()
    const compositeDebt_4 = (await troveManagerTester.getCompositeDebt(dec(1, 27))).toString()
    assert.isAtMost(th.getDifference(compositeDebt_4, '1000000200000000000000000000'), 100000000000)

    /*
    ETH:USD price = 1000000 $/E (1 million)
    coll = 300000000 ETH   (300 million)
    debt = 54321.123456789 LUSD
   -> Expect composite debt = (54321.123456789 + 200) = 54521.123456789 LUSD */
    await priceFeed.setPrice(dec(1, 24))
    const price_3 = await priceFeed.getPrice()
    const compositeDebt_5 = (await troveManagerTester.getCompositeDebt('54321123456789000000000')).toString()
    assert.equal(compositeDebt_5, '54521123456789000000000')
  })

  // --- Test ICRs with virtual debt ---
  it('getCurrentICR(): Incorporates virtual debt, and returns the correct ICR for new troves', async () => {
    const price = await priceFeed.getPrice()
    await openTrove({ ICR: toBN(dec(200, 18)), extraParams: { from: whale } })

    // A opens with 1 ETH, 110 LUSD
    await openTrove({ ICR: toBN('1818181818181818181'), extraParams: { from: alice } })
    const alice_ICR = (await troveManager.getCurrentICR(alice, price)).toString()
    // Expect aliceICR = (1 * 200) / (110) = 181.81%
    assert.isAtMost(th.getDifference(alice_ICR, '1818181818181818181'), 1000)

    // B opens with 0.5 ETH, 50 LUSD
    await openTrove({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
    const bob_ICR = (await troveManager.getCurrentICR(bob, price)).toString()
    // Expect Bob's ICR = (0.5 * 200) / 50 = 200%
    assert.isAtMost(th.getDifference(bob_ICR, dec(2, 18)), 1000)

    // F opens with 1 ETH, 100 LUSD
    await openTrove({ ICR: toBN(dec(2, 18)), extraLUSDAmount: dec(100, 18), extraParams: { from: flyn } })
    const flyn_ICR = (await troveManager.getCurrentICR(flyn, price)).toString()
    // Expect Flyn's ICR = (1 * 200) / 100 = 200%
    assert.isAtMost(th.getDifference(flyn_ICR, dec(2, 18)), 1000)

    // C opens with 2.5 ETH, 160 LUSD
    await openTrove({ ICR: toBN(dec(3125, 15)), extraParams: { from: carol } })
    const carol_ICR = (await troveManager.getCurrentICR(carol, price)).toString()
    // Expect Carol's ICR = (2.5 * 200) / (160) = 312.50%
    assert.isAtMost(th.getDifference(carol_ICR, '3125000000000000000'), 1000)

    // D opens with 1 ETH, 0 LUSD
    await openTrove({ ICR: toBN(dec(4, 18)), extraParams: { from: dennis } })
    const dennis_ICR = (await troveManager.getCurrentICR(dennis, price)).toString()
    // Expect Dennis's ICR = (1 * 200) / (50) = 400.00%
    assert.isAtMost(th.getDifference(dennis_ICR, dec(4, 18)), 1000)

    // E opens with 4405.45 ETH, 32598.35 LUSD
    await openTrove({ ICR: toBN('27028668628933700000'), extraParams: { from: erin } })
    const erin_ICR = (await troveManager.getCurrentICR(erin, price)).toString()
    // Expect Erin's ICR = (4405.45 * 200) / (32598.35) = 2702.87%
    assert.isAtMost(th.getDifference(erin_ICR, '27028668628933700000'), 100000)

    // H opens with 1 ETH, 180 LUSD
    await openTrove({ ICR: toBN('1111111111111111111'), extraParams: { from: harriet } })
    const harriet_ICR = (await troveManager.getCurrentICR(harriet, price)).toString()
    // Expect Harriet's ICR = (1 * 200) / (180) = 111.11%
    assert.isAtMost(th.getDifference(harriet_ICR, '1111111111111111111'), 1000)
  })

  // --- Event emission in single liquidation ---

  it('Gas compensation from pool-offset liquidations. Liquidation event emits the correct gas compensation and total liquidated coll and debt', async () => {
    await deploymentHelper.mintLUSD(lusdToken, liquidator);
    await openTrove({ ICR: toBN(dec(2000, 18)), extraParams: { from: whale } })

    // A-E open troves
    const { totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(2, 18)), extraLUSDAmount: dec(100, 18), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(2, 18)), extraLUSDAmount: dec(200, 18), extraParams: { from: bob } })
    await openTrove({ ICR: toBN(dec(2, 18)), extraLUSDAmount: dec(300, 18), extraParams: { from: carol } })
    await openTrove({ ICR: toBN(dec(2, 18)), extraLUSDAmount: A_totalDebt, extraParams: { from: dennis } })
    await openTrove({ ICR: toBN(dec(2, 18)), extraLUSDAmount: B_totalDebt, extraParams: { from: erin } })

    // --- Price drops to 105 ---
    await priceFeed.setPrice(dec(105, 18))
    const price_1 = await priceFeed.getPrice()

    /*
    ETH:USD price = 105
    -> Expect 0.5% of collaterall to be sent to liquidator, as gas compensation */

    // Check collateral value in USD is < $10
    const aliceColl = (await troveManager.Troves(alice))[1]
    const aliceDebt = (await troveManager.Troves(alice))[0]

    // Liquidate A (use 0 gas price to easily check the amount the compensation amount the liquidator receives)
    const liquidationTxA = await troveManager.liquidate(alice, { from: liquidator, gasPrice: GAS_PRICE })

    const expectedGasComp_A = aliceColl.mul(th.toBN(5)).div(th.toBN(1000))
    const expectedLiquidatedColl_A = aliceColl.sub(expectedGasComp_A)
    const expectedLiquidatedDebt_A =  aliceDebt

    const [loggedDebt_A, loggedColl_A, loggedGasComp_A, ] = th.getEmittedLiquidationValues(liquidationTxA)

    assert.isAtMost(th.getDifference(expectedLiquidatedDebt_A, loggedDebt_A), 1000)
    assert.isAtMost(th.getDifference(expectedLiquidatedColl_A, loggedColl_A), 1000)
    assert.isAtMost(th.getDifference(expectedGasComp_A, loggedGasComp_A), 1000)

    // --- Price drops to 101 ---
    await priceFeed.setPrice(dec(101, 18))

    // Check collateral value in USD is < $10
    const bobColl = (await troveManager.Troves(bob))[1]
    const bobDebt = (await troveManager.Troves(bob))[0]

    // Liquidate B (use 0 gas price to easily check the amount the compensation amount the liquidator receives)
    const liquidationTxB = await troveManager.liquidate(bob, { from: liquidator, gasPrice: GAS_PRICE })

    const expectedGasComp_B = bobColl.mul(th.toBN(5)).div(th.toBN(1000))
    const expectedLiquidatedColl_B = bobColl.sub(expectedGasComp_B)
    const expectedLiquidatedDebt_B =  bobDebt

    const [loggedDebt_B, loggedColl_B, loggedGasComp_B, ] = th.getEmittedLiquidationValues(liquidationTxB)

    assert.isAtMost(th.getDifference(expectedLiquidatedDebt_B, loggedDebt_B), 1000)
    assert.isAtMost(th.getDifference(expectedLiquidatedColl_B, loggedColl_B), 1000)
    assert.isAtMost(th.getDifference(expectedGasComp_B, loggedGasComp_B), 1000)
  })


  it('gas compensation from pool-offset liquidations. Liquidation event emits the correct gas compensation and total liquidated coll and debt', async () => {
    await deploymentHelper.mintLUSD(lusdToken, liquidator);
    await priceFeed.setPrice(dec(400, 18))
    await openTrove({ ICR: toBN(dec(2000, 18)), extraParams: { from: whale } })

    // A-E open troves
    await openTrove({ ICR: toBN(dec(2, 18)), extraLUSDAmount: dec(200, 18), extraParams: { from: alice } })
    await openTrove({ ICR: toBN(dec(120, 16)), extraLUSDAmount: dec(5000, 18), extraParams: { from: bob } })
    await openTrove({ ICR: toBN(dec(60, 18)), extraLUSDAmount: dec(600, 18), extraParams: { from: carol } })
    await openTrove({ ICR: toBN(dec(80, 18)), extraLUSDAmount: dec(1, 23), extraParams: { from: dennis } })
    await openTrove({ ICR: toBN(dec(80, 18)), extraLUSDAmount: dec(1, 23), extraParams: { from: erin } })

    // --- Price drops to 199.999 ---
    await priceFeed.setPrice('200999000000000000000')
    const price_1 = await priceFeed.getPrice()

    /*
    ETH:USD price = 200.999
    Alice coll = 1 ETH. Value: $200.999
    0.5% of coll  = 0.05 ETH. Value: (0.05 * 200.999) = $10.04995
    */

    const aliceColl = (await troveManager.Troves(alice))[1]
    const aliceDebt = (await troveManager.Troves(alice))[0]
    const aliceCollValueInUSD = (await borrowerOperationsTester.getUSDValue(aliceColl, price_1))
    assert.isTrue(aliceCollValueInUSD.gt(th.toBN(dec(10, 18))))

    // Check value of 0.5% of collateral in USD is < $10
    const _0pt5percent_aliceColl = aliceColl.div(web3.utils.toBN('200'))

    const aliceICR = await troveManager.getCurrentICR(alice, price_1)
    assert.isTrue(aliceICR.lt(mv._MCR))

    // Liquidate A (use 0 gas price to easily check the amount the compensation amount the liquidator receives)
    const liquidationTxA = await troveManager.liquidate(alice, { from: liquidator, gasPrice: GAS_PRICE })

    const expectedGasComp_A = _0pt5percent_aliceColl
    const expectedLiquidatedColl_A = aliceColl.sub(expectedGasComp_A)
    const expectedLiquidatedDebt_A =  aliceDebt

    const [loggedDebt_A, loggedColl_A, loggedGasComp_A, ] = th.getEmittedLiquidationValues(liquidationTxA)

    assert.isAtMost(th.getDifference(expectedLiquidatedDebt_A, loggedDebt_A), 1000)
    assert.isAtMost(th.getDifference(expectedLiquidatedColl_A, loggedColl_A), 1000)
    assert.isAtMost(th.getDifference(expectedGasComp_A, loggedGasComp_A), 1000)

      // --- Price changes to 335 ---
      await priceFeed.setPrice(dec(335, 18))
      const price_2 = await priceFeed.getPrice()

    const bobColl = (await troveManager.Troves(bob))[1]
    const bobDebt = (await troveManager.Troves(bob))[0]

    const bobICR = await troveManager.getCurrentICR(bob, price_2)
    assert.isTrue(bobICR.lte(mv._MCR))

    // Liquidate B (use 0 gas price to easily check the amount the compensation amount the liquidator receives
    const liquidationTxB = await troveManager.liquidate(bob, { from: liquidator, gasPrice: GAS_PRICE })

    const _0pt5percent_bobColl = bobColl.div(web3.utils.toBN('200'))
    const expectedGasComp_B = _0pt5percent_bobColl
    const expectedLiquidatedColl_B = bobColl.sub(expectedGasComp_B)
    const expectedLiquidatedDebt_B =  bobDebt

    const [loggedDebt_B, loggedColl_B, loggedGasComp_B, ] = th.getEmittedLiquidationValues(liquidationTxB)

    assert.isAtMost(th.getDifference(expectedLiquidatedDebt_B, loggedDebt_B), 1000)
    assert.isAtMost(th.getDifference(expectedLiquidatedColl_B, loggedColl_B), 1000)
    assert.isAtMost(th.getDifference(expectedGasComp_B, loggedGasComp_B), 1000)
  })


  it('gas compensation from pool-offset liquidations: 0.5% collateral > $10 in value. Liquidation event emits the correct gas compensation and total liquidated coll and debt', async () => {
    await deploymentHelper.mintLUSD(lusdToken, liquidator);
    // open troves
    await priceFeed.setPrice(dec(400, 18))
    await openTrove({ ICR: toBN(dec(200, 18)), extraParams: { from: whale } })

    // A-E open troves
    await openTrove({ ICR: toBN(dec(2, 18)), extraLUSDAmount: dec(2000, 18), extraParams: { from: alice } })
    await openTrove({ ICR: toBN(dec(1875, 15)), extraLUSDAmount: dec(8000, 18), extraParams: { from: bob } })
    await openTrove({ ICR: toBN(dec(2, 18)), extraLUSDAmount: dec(600, 18), extraParams: { from: carol } })
    await openTrove({ ICR: toBN(dec(4, 18)), extraLUSDAmount: dec(1, 23), extraParams: { from: dennis } })
    await openTrove({ ICR: toBN(dec(4, 18)), extraLUSDAmount: dec(1, 23), extraParams: { from: erin } })

    await priceFeed.setPrice(dec(215, 18))
    const price_1 = await priceFeed.getPrice()

    const aliceColl = (await troveManager.Troves(alice))[1]
    const aliceDebt = (await troveManager.Troves(alice))[0]
    const _0pt5percent_aliceColl = aliceColl.div(web3.utils.toBN('200'))

    const aliceICR = await troveManager.getCurrentICR(alice, price_1)
    assert.isTrue(aliceICR.lt(mv._MCR))

    // Liquidate A (use 0 gas price to easily check the amount the compensation amount the liquidator receives)
    const liquidationTxA = await troveManager.liquidate(alice, { from: liquidator, gasPrice: GAS_PRICE })

    const expectedGasComp_A = _0pt5percent_aliceColl
    const expectedLiquidatedColl_A = aliceColl.sub(_0pt5percent_aliceColl)
    const expectedLiquidatedDebt_A =  aliceDebt

    const [loggedDebt_A, loggedColl_A, loggedGasComp_A, ] = th.getEmittedLiquidationValues(liquidationTxA)

    assert.isAtMost(th.getDifference(expectedLiquidatedDebt_A, loggedDebt_A), 1000)
    assert.isAtMost(th.getDifference(expectedLiquidatedColl_A, loggedColl_A), 1000)
    assert.isAtMost(th.getDifference(expectedGasComp_A, loggedGasComp_A), 1000)

    const bobColl = (await troveManager.Troves(bob))[1]
    const bobDebt = (await troveManager.Troves(bob))[0]
    const _0pt5percent_bobColl = bobColl.div(web3.utils.toBN('200'))

    const bobICR = await troveManager.getCurrentICR(bob, price_1)
    assert.isTrue(bobICR.lt(mv._MCR))

    // Liquidate B (use 0 gas price to easily check the amount the compensation amount the liquidator receives)
    const liquidationTxB = await troveManager.liquidate(bob, { from: liquidator, gasPrice: GAS_PRICE })

    const expectedGasComp_B = _0pt5percent_bobColl
    const expectedLiquidatedColl_B = bobColl.sub(_0pt5percent_bobColl)
    const expectedLiquidatedDebt_B =  bobDebt

    const [loggedDebt_B, loggedColl_B, loggedGasComp_B, ] = th.getEmittedLiquidationValues(liquidationTxB)

    assert.isAtMost(th.getDifference(expectedLiquidatedDebt_B, loggedDebt_B), 1000)
    assert.isAtMost(th.getDifference(expectedLiquidatedColl_B, loggedColl_B), 1000)
    assert.isAtMost(th.getDifference(expectedGasComp_B, loggedGasComp_B), 1000)
  })

  // liquidateTroves - full redistribution
  it('liquidateTroves(): full redistribution. Compensates the correct amount, and liquidates the remainder', async () => {
    await priceFeed.setPrice(dec(1000, 18))

    await openTrove({ ICR: toBN(dec(200, 18)), extraParams: { from: whale } })

    // A-D open troves
    await openTrove({ ICR: toBN(dec(118, 16)), extraLUSDAmount: dec(2000, 18), extraParams: { from: alice } })
    await openTrove({ ICR: toBN(dec(226, 16)), extraLUSDAmount: dec(8000, 18), extraParams: { from: bob } })
    await openTrove({ ICR: toBN(dec(488, 16)), extraLUSDAmount: dec(600, 18), extraParams: { from: carol } })
    await openTrove({ ICR: toBN(dec(445, 16)), extraLUSDAmount: dec(1, 23), extraParams: { from: dennis } })

    const LUSDinDefaultPool_0 = await defaultPool.getLUSDDebt()

    // price drops to 200
    await priceFeed.setPrice(dec(200, 18))
    const price = await priceFeed.getPrice()

    // Check A, B, C, D have ICR < MCR
    assert.isTrue((await troveManager.getCurrentICR(alice, price)).lt(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(bob, price)).lt(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(carol, price)).lt(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(dennis, price)).lt(mv._MCR))

    // --- Check value of of A's collateral is < $10, and value of B,C,D collateral are > $10  ---
    const aliceColl = (await troveManager.Troves(alice))[1]
    const bobColl = (await troveManager.Troves(bob))[1]
    const carolColl = (await troveManager.Troves(carol))[1]
    const dennisColl = (await troveManager.Troves(dennis))[1]

    // --- Check value of 0.5% of A, B, and C's collateral is <$10, and value of 0.5% of D's collateral is > $10 ---
    const _0pt5percent_aliceColl = aliceColl.div(web3.utils.toBN('200'))
    const _0pt5percent_bobColl = bobColl.div(web3.utils.toBN('200'))
    const _0pt5percent_carolColl = carolColl.div(web3.utils.toBN('200'))
    const _0pt5percent_dennisColl = dennisColl.div(web3.utils.toBN('200'))

    const collGasCompensation = await troveManagerTester.getCollGasCompensation(price)
    assert.equal(collGasCompensation, dec(1 , 18))

    /* Expect total gas compensation =
       0.5% of [A_coll + B_coll + C_coll + D_coll]
    */
    const expectedGasComp = _0pt5percent_aliceColl
          .add(_0pt5percent_bobColl)
          .add(_0pt5percent_carolColl)
          .add(_0pt5percent_dennisColl)

    /* Expect liquidated coll =
    0.95% of [A_coll + B_coll + C_coll + D_coll]
    */
    const expectedLiquidatedColl = aliceColl.sub(_0pt5percent_aliceColl)
      .add(bobColl.sub(_0pt5percent_bobColl))
      .add(carolColl.sub(_0pt5percent_carolColl))
      .add(dennisColl.sub(_0pt5percent_dennisColl))

    // Liquidate troves A-D
    const liquidatorBalance_before = web3.utils.toBN(await wstETHTokenMock.balanceOf(liquidator))
    await troveManager.liquidateTroves(4, { from: liquidator, gasPrice: GAS_PRICE })
    const liquidatorBalance_after = web3.utils.toBN(await wstETHTokenMock.balanceOf(liquidator))

    // Check LUSD in DefaultPool has decreased
    const LUSDinDefaultPool_1 = await defaultPool.getLUSDDebt()
    assert.isTrue(LUSDinDefaultPool_1.gt(LUSDinDefaultPool_0))

    // Check liquidator's balance has increased by the expected compensation amount
    const compensationReceived = (liquidatorBalance_after.sub(liquidatorBalance_before)).toString()

    assert.isAtMost(th.getDifference(expectedGasComp, compensationReceived), 1000)

    // Check ETH in defaultPool now equals the expected liquidated collateral
    const ETHinDefaultPool = (await defaultPool.getETH()).toString()
    assert.isAtMost(th.getDifference(expectedLiquidatedColl, ETHinDefaultPool), 1000)
  })

  //  --- event emission in liquidation sequence ---
  it('liquidateTroves(): full offset. Liquidation event emits the correct gas compensation and total liquidated coll and debt', async () => {
    await deploymentHelper.mintLUSD(lusdToken, liquidator);
    await priceFeed.setPrice(dec(1000, 18))

    await openTrove({ ICR: toBN(dec(2000, 18)), extraParams: { from: whale } })

    // A-F open troves
    const { totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(118, 16)), extraLUSDAmount: dec(2000, 18), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(526, 16)), extraLUSDAmount: dec(8000, 18), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(488, 16)), extraLUSDAmount: dec(600, 18), extraParams: { from: carol } })
    const { totalDebt: D_totalDebt } = await openTrove({ ICR: toBN(dec(545, 16)), extraLUSDAmount: dec(1, 23), extraParams: { from: dennis } })
    await openTrove({ ICR: toBN(dec(10, 18)), extraLUSDAmount: dec(1, 23), extraParams: { from: erin } })
    await openTrove({ ICR: toBN(dec(10, 18)), extraLUSDAmount: dec(1, 23), extraParams: { from: flyn } })

    // price drops to 200
    await priceFeed.setPrice(dec(200, 18))
    const price = await priceFeed.getPrice()

    // Check A, B, C, D have ICR < MCR
    assert.isTrue((await troveManager.getCurrentICR(alice, price)).lt(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(bob, price)).lt(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(carol, price)).lt(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(dennis, price)).lt(mv._MCR))

    // Check E, F have ICR > MCR
    assert.isTrue((await troveManager.getCurrentICR(erin, price)).gt(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(flyn, price)).gt(mv._MCR))


    // --- Check value of of A's collateral is < $10, and value of B,C,D collateral are > $10  ---
    const aliceColl = (await troveManager.Troves(alice))[1]
    const bobColl = (await troveManager.Troves(bob))[1]
    const carolColl = (await troveManager.Troves(carol))[1]
    const dennisColl = (await troveManager.Troves(dennis))[1]

    // --- Check value of 0.5% of A, B, and C's collateral is <$10, and value of 0.5% of D's collateral is > $10 ---
    const _0pt5percent_aliceColl = aliceColl.div(web3.utils.toBN('200'))
    const _0pt5percent_bobColl = bobColl.div(web3.utils.toBN('200'))
    const _0pt5percent_carolColl = carolColl.div(web3.utils.toBN('200'))
    const _0pt5percent_dennisColl = dennisColl.div(web3.utils.toBN('200'))

    const collGasCompensation = await troveManagerTester.getCollGasCompensation(price)
    assert.equal(collGasCompensation, dec(1, 18))

    /* Expect total gas compensation =
    0.5% of [A_coll + B_coll + C_coll + D_coll]
    */
    const expectedGasComp = _0pt5percent_aliceColl
      .add(_0pt5percent_bobColl)
      .add(_0pt5percent_carolColl)
      .add(_0pt5percent_dennisColl)

    /* Expect liquidated coll =
       0.95% of [A_coll + B_coll + C_coll + D_coll]
    */
    const expectedLiquidatedColl = aliceColl.sub(_0pt5percent_aliceColl)
          .add(bobColl.sub(_0pt5percent_bobColl))
          .add(carolColl.sub(_0pt5percent_carolColl))
          .add(dennisColl.sub(_0pt5percent_dennisColl))

    // Expect liquidatedDebt = 51 + 190 + 1025 + 13510 = 14646 LUSD
    const expectedLiquidatedDebt = A_totalDebt.add(B_totalDebt).add(C_totalDebt).add(D_totalDebt)

    // Liquidate troves A-D
    const liquidationTxData = await troveManager.liquidateTroves(4, { from: liquidator, gasPrice: GAS_PRICE })

    // Get data from the liquidation event logs
    const [loggedDebt, loggedColl, loggedGasComp, ] = th.getEmittedLiquidationValues(liquidationTxData)

    assert.isAtMost(th.getDifference(expectedLiquidatedDebt, loggedDebt), 1000)
    assert.isAtMost(th.getDifference(expectedLiquidatedColl, loggedColl), 1000)
    assert.isAtMost(th.getDifference(expectedGasComp, loggedGasComp), 1000)
  })

  it('liquidateTroves(): full redistribution. Liquidation event emits the correct gas compensation and total liquidated coll and debt', async () => {
    await priceFeed.setPrice(dec(1000, 18))

    await openTrove({ ICR: toBN(dec(2000, 18)), extraParams: { from: whale } })

    // A-F open troves
    const { totalDebt: A_totalDebt } = await openTrove({ ICR: toBN(dec(118, 16)), extraLUSDAmount: dec(2000, 18), extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openTrove({ ICR: toBN(dec(226, 16)), extraLUSDAmount: dec(8000, 18), extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openTrove({ ICR: toBN(dec(488, 16)), extraLUSDAmount: dec(600, 18), extraParams: { from: carol } })
    const { totalDebt: D_totalDebt } = await openTrove({ ICR: toBN(dec(345, 16)), extraLUSDAmount: dec(1, 23), extraParams: { from: dennis } })
    await openTrove({ ICR: toBN(dec(10, 18)), extraLUSDAmount: dec(1, 23), extraParams: { from: erin } })
    await openTrove({ ICR: toBN(dec(10, 18)), extraLUSDAmount: dec(1, 23), extraParams: { from: flyn } })

    const LUSDinDefaultPool_0 = await defaultPool.getLUSDDebt()

    // price drops to 200
    await priceFeed.setPrice(dec(200, 18))
    const price = await priceFeed.getPrice()

    // Check A, B, C, D have ICR < MCR
    assert.isTrue((await troveManager.getCurrentICR(alice, price)).lt(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(bob, price)).lt(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(carol, price)).lt(mv._MCR))
    assert.isTrue((await troveManager.getCurrentICR(dennis, price)).lt(mv._MCR))

    const aliceColl = (await troveManager.Troves(alice))[1]
    const bobColl = (await troveManager.Troves(bob))[1]
    const carolColl = (await troveManager.Troves(carol))[1]
    const dennisColl = (await troveManager.Troves(dennis))[1]

    // --- Check value of 0.5% of A, B, and C's collateral is <$10, and value of 0.5% of D's collateral is > $10 ---
    const _0pt5percent_aliceColl = aliceColl.div(web3.utils.toBN('200'))
    const _0pt5percent_bobColl = bobColl.div(web3.utils.toBN('200'))
    const _0pt5percent_carolColl = carolColl.div(web3.utils.toBN('200'))
    const _0pt5percent_dennisColl = dennisColl.div(web3.utils.toBN('200'))

    /* Expect total gas compensation =
    0.5% of [A_coll + B_coll + C_coll + D_coll]
    */
    const expectedGasComp = _0pt5percent_aliceColl
      .add(_0pt5percent_bobColl)
      .add(_0pt5percent_carolColl)
      .add(_0pt5percent_dennisColl).toString()

    /* Expect liquidated coll =
    0.95% of [A_coll + B_coll + C_coll + D_coll]
    */
    const expectedLiquidatedColl = aliceColl.sub(_0pt5percent_aliceColl)
      .add(bobColl.sub(_0pt5percent_bobColl))
      .add(carolColl.sub(_0pt5percent_carolColl))
      .add(dennisColl.sub(_0pt5percent_dennisColl))

    // Expect liquidatedDebt = 51 + 190 + 1025 + 13510 = 14646 LUSD
    const expectedLiquidatedDebt = A_totalDebt.add(B_totalDebt).add(C_totalDebt).add(D_totalDebt)

    // Liquidate troves A-D
    const liquidationTxData = await troveManager.liquidateTroves(4, { from: liquidator, gasPrice: GAS_PRICE })

    // Get data from the liquidation event logs
    const [loggedDebt, loggedColl, loggedGasComp, ] = th.getEmittedLiquidationValues(liquidationTxData)

    assert.isAtMost(th.getDifference(expectedLiquidatedDebt, loggedDebt), 1000)
    assert.isAtMost(th.getDifference(expectedLiquidatedColl, loggedColl), 1000)
    assert.isAtMost(th.getDifference(expectedGasComp, loggedGasComp), 1000)
  })

  // --- Trove ordering by ICR tests ---

  it('Trove ordering: same collateral, decreasing debt. Price successively increases. Troves should maintain ordering by ICR', async () => {
    const _10_accounts = accounts.slice(1, 11)
    await th.fillAccountsWithWstETH(contracts, _10_accounts)

    let debt = 50
    // create 10 troves, constant coll, descending debt 100 to 90 LUSD
    for (const account of _10_accounts) {

      const debtString = debt.toString().concat('000000000000000000')
      await wstETHTokenMock.approve(activePool.address, dec(30, 'ether'), { from: account})
      await openTrove({ extraLUSDAmount: debtString, amount: dec(30, 'ether'), extraParams: { from: account } })

      const squeezedTroveAddr = th.squeezeAddr(account)

      debt -= 1
    }

    const initialPrice = await priceFeed.getPrice()
    const firstColl = (await troveManager.Troves(_10_accounts[0]))[1]

    // Vary price 200-210
    let price = 200
    while (price < 210) {

      const priceString = price.toString().concat('000000000000000000')
      await priceFeed.setPrice(priceString)

      const ICRList = []
      const coll_firstTrove = (await troveManager.Troves(_10_accounts[0]))[1]
      const gasComp_firstTrove = (await troveManagerTester.getCollGasCompensation(coll_firstTrove)).toString()

      for (account of _10_accounts) {
        // Check gas compensation is the same for all troves
        const coll = (await troveManager.Troves(account))[1]
        const gasCompensation = (await troveManagerTester.getCollGasCompensation(coll)).toString()

        assert.equal(gasCompensation, gasComp_firstTrove)

        const ICR = await troveManager.getCurrentICR(account, price)
        ICRList.push(ICR)


        // Check trove ordering by ICR is maintained
        if (ICRList.length > 1) {
          const prevICR = ICRList[ICRList.length - 2]

          try {
            assert.isTrue(ICR.gte(prevICR))
          } catch (error) {
            console.log(`ETH price at which trove ordering breaks: ${price}`)
            logICRs(ICRList)
          }
        }

        price += 1
      }
    }
  })

  it('Trove ordering: increasing collateral, constant debt. Price successively increases. Troves should maintain ordering by ICR', async () => {
    const _20_accounts = accounts.slice(1, 21)
    await th.fillAccountsWithWstETH(contracts, _20_accounts);

    let coll = 50
    // create 20 troves, increasing collateral, constant debt = 100LUSD
    for (const account of _20_accounts) {

      const collString = coll.toString().concat('000000000000000000')
      await wstETHTokenMock.approve(activePool.address, collString, { from: account})
      await openTrove({ extraLUSDAmount: dec(100, 18), amount: collString, extraParams: { from: account } })

      coll += 5
    }

    const initialPrice = await priceFeed.getPrice()

    // Vary price
    let price = 1
    while (price < 300) {

      const priceString = price.toString().concat('000000000000000000')
      await priceFeed.setPrice(priceString)

      const ICRList = []

      for (account of _20_accounts) {
        const ICR = await troveManager.getCurrentICR(account, price)
        ICRList.push(ICR)

        // Check trove ordering by ICR is maintained
        if (ICRList.length > 1) {
          const prevICR = ICRList[ICRList.length - 2]

          try {
            assert.isTrue(ICR.gte(prevICR))
          } catch (error) {
            console.log(`ETH price at which trove ordering breaks: ${price}`)
            logICRs(ICRList)
          }
        }

        price += 10
      }
    }
  })

  it('Trove ordering: Constant raw collateral ratio (excluding virtual debt). Price successively increases. Troves should maintain ordering by ICR', async () => {
    let collVals = [1, 5, 10, 25, 50, 100, 500, 1000, 5000, 10000, 50000, 100000, 500000, 1000000, 5000000].map(v => v * 20)
    const accountsList = accounts.slice(1, collVals.length + 1)
    await th.fillAccountsWithWstETH(contracts, accountsList)

    let accountIdx = 0
    for (const coll of collVals) {

      const debt = coll * 110

      const account = accountsList[accountIdx]
      const collString = coll.toString().concat('000000000000000000')
      await wstETHTokenMock.approve(activePool.address, collString, { from: account})
      await openTrove({ extraLUSDAmount: dec(100, 18), amount: collString, extraParams: { from: account } })

      accountIdx += 1
    }

    const initialPrice = await priceFeed.getPrice()

    // Vary price
    let price = 1
    while (price < 300) {

      const priceString = price.toString().concat('000000000000000000')
      await priceFeed.setPrice(priceString)

      const ICRList = []

      for (account of accountsList) {
        const ICR = await troveManager.getCurrentICR(account, price)
        ICRList.push(ICR)

        // Check trove ordering by ICR is maintained
        if (ICRList.length > 1) {
          const prevICR = ICRList[ICRList.length - 2]

          try {
            assert.isTrue(ICR.gte(prevICR))
          } catch (error) {
            console.log(error)
            console.log(`ETH price at which trove ordering breaks: ${price}`)
            logICRs(ICRList)
          }
        }

        price += 10
      }
    }
  })
})

