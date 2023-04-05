const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")
const PositionManagerTester = artifacts.require("./PositionManagerTester.sol")
const RToken = artifacts.require("RToken")

const th = testHelpers.TestHelper
const dec = th.dec
const toBN = th.toBN
const mv = testHelpers.MoneyValues

const GAS_PRICE = 10000000

/// TODO IMPORTANT: fix skipped tests as part of https://github.com/tempusfinance/raft/issues/14
contract('Gas compensation tests', async accounts => {
  const [
    owner, liquidator,
    alice, bob, carol, dennis, erin, flyn, harriet,
    whale] = accounts;

  let priceFeed
  let rToken
  let positionManager
  let wstETHTokenMock

  let contracts
  let positionManagerTester

  const openPosition = async (params) => th.openPosition(contracts, params)

  const logICRs = (ICRList) => {
    for (let i = 0; i < ICRList.length; i++) {
      console.log(`account: ${i + 1} ICR: ${ICRList[i].toString()}`)
    }
  }

  beforeEach(async () => {
    contracts = await deploymentHelper.deployLiquityCore(owner)

    await th.fillAccountsWithWstETH(contracts, [
      owner, liquidator,
      alice, bob, carol, dennis, erin, flyn, harriet,
      whale,
    ])

    priceFeed = contracts.priceFeedTestnet
    rToken = contracts.rToken
    positionManager = contracts.positionManager
    positionManagerTester = contracts.positionManager
    wstETHTokenMock = contracts.wstETHTokenMock
  })

  // --- Raw gas compensation calculations ---

  it('getCollGasCompensation(): returns the 0.5% of collateral if it is < $10 in value', async () => {
    /*
    ETH:USD price = 1
    coll = 1 ETH: $1 in value
    -> Expect 0.5% of collaterall as gas compensation */
    await priceFeed.setPrice(dec(1, 18))
    // const price_1 = await priceFeed.getPrice()
    const gasCompensation_1 = (await positionManagerTester.getCollGasCompensation(dec(1, 'ether'))).toString()
    assert.equal(gasCompensation_1, dec(5, 15))

    /*
    ETH:USD price = 28.4
    coll = 0.1 ETH: $2.84 in value
    -> Expect 0.5% of collaterall as gas compensation */
    await priceFeed.setPrice('28400000000000000000')
    // const price_2 = await priceFeed.getPrice()
    const gasCompensation_2 = (await positionManagerTester.getCollGasCompensation(dec(100, 'finney'))).toString()
    assert.equal(gasCompensation_2, dec(5, 14))

    /*
    ETH:USD price = 1000000000 (1 billion)
    coll = 0.000000005 ETH (5e9 wei): $5 in value
    -> Expect 0.5% of collaterall as gas compensation */
    await priceFeed.setPrice(dec(1, 27))
    // const price_3 = await priceFeed.getPrice()
    const gasCompensation_3 = (await positionManagerTester.getCollGasCompensation('5000000000')).toString()
    assert.equal(gasCompensation_3, '25000000')
  })

  it('getCollGasCompensation(): returns 0.5% of collaterall when 0.5% of collateral < $10 in value', async () => {
    const price = await priceFeed.getPrice()
    assert.equal(price, dec(200, 18))

    /*
    ETH:USD price = 200
    coll = 9.999 ETH
    0.5% of coll = 0.04995 ETH. USD value: $9.99
    -> Expect 0.5% of collaterall as gas compensation */
    const gasCompensation_1 = (await positionManagerTester.getCollGasCompensation('9999000000000000000')).toString()
    assert.equal(gasCompensation_1, '49995000000000000')

    /* ETH:USD price = 200
     coll = 0.055 ETH
     0.5% of coll = 0.000275 ETH. USD value: $0.055
     -> Expect 0.5% of collaterall as gas compensation */
    const gasCompensation_2 = (await positionManagerTester.getCollGasCompensation('55000000000000000')).toString()
    assert.equal(gasCompensation_2, dec(275, 12))

    /* ETH:USD price = 200
    coll = 6.09232408808723580 ETH
    0.5% of coll = 0.004995 ETH. USD value: $6.09
    -> Expect 0.5% of collaterall as gas compensation */
    const gasCompensation_3 = (await positionManagerTester.getCollGasCompensation('6092324088087235800')).toString()
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
    const gasCompensation = (await positionManagerTester.getCollGasCompensation(dec(10, 'ether'))).toString()
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
    const gasCompensation_1 = (await positionManagerTester.getCollGasCompensation(dec(100, 'ether'))).toString()
    assert.equal(gasCompensation_1, dec(500, 'finney'))

    /*
    ETH:USD price = 200 $/E
    coll = 10.001 ETH
    0.5% of coll = 0.050005 ETH. USD value: $10.001
    -> Expect $100 gas compensation, i.e.  0.050005  ETH */
    const gasCompensation_2 = (await positionManagerTester.getCollGasCompensation('10001000000000000000')).toString()
    assert.equal(gasCompensation_2, '50005000000000000')

    /*
    ETH:USD price = 200 $/E
    coll = 37.5 ETH
    0.5% of coll = 0.1875 ETH. USD value: $37.5
    -> Expect $37.5 gas compensation i.e.  0.1875  ETH */
    const gasCompensation_3 = (await positionManagerTester.getCollGasCompensation('37500000000000000000')).toString()
    assert.equal(gasCompensation_3, '187500000000000000')

    /*
    ETH:USD price = 45323.54542 $/E
    coll = 94758.230582309850 ETH
    0.5% of coll = 473.7911529 ETH. USD value: $21473894.84
    -> Expect $21473894.8385808 gas compensation, i.e.  473.7911529115490  ETH */
    await priceFeed.setPrice('45323545420000000000000')
    const gasCompensation_4 = await positionManagerTester.getCollGasCompensation('94758230582309850000000')
    assert.isAtMost(th.getDifference(gasCompensation_4, '473791152911549000000'), 1000000)

    /*
    ETH:USD price = 1000000 $/E (1 million)
    coll = 300000000 ETH   (300 million)
    0.5% of coll = 1500000 ETH. USD value: $150000000000
    -> Expect $150000000000 gas compensation, i.e. 1500000 ETH */
    await priceFeed.setPrice(dec(1, 24))
    const price_2 = await priceFeed.getPrice()
    const gasCompensation_5 = (await positionManagerTester.getCollGasCompensation('300000000000000000000000000')).toString()
    assert.equal(gasCompensation_5, '1500000000000000000000000')
  })

  // --- Test ICRs with virtual debt ---
  it('getCurrentICR(): Incorporates virtual debt, and returns the correct ICR for new positions', async () => {
    const price = await priceFeed.getPrice()
    await openPosition({ ICR: toBN(dec(200, 18)), extraParams: { from: whale } })

    // A opens with 1 ETH, 110 R
    await openPosition({ ICR: toBN('1818181818181818181'), extraParams: { from: alice } })
    const alice_ICR = (await positionManager.getCurrentICR(alice, price)).toString()
    // Expect aliceICR = (1 * 200) / (110) = 181.81%
    assert.isAtMost(th.getDifference(alice_ICR, '1818181818181818181'), 1000)

    // B opens with 0.5 ETH, 50 R
    await openPosition({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
    const bob_ICR = (await positionManager.getCurrentICR(bob, price)).toString()
    // Expect Bob's ICR = (0.5 * 200) / 50 = 200%
    assert.isAtMost(th.getDifference(bob_ICR, dec(2, 18)), 1000)

    // F opens with 1 ETH, 100 R
    await openPosition({ ICR: toBN(dec(2, 18)), extraRAmount: dec(100, 18), extraParams: { from: flyn } })
    const flyn_ICR = (await positionManager.getCurrentICR(flyn, price)).toString()
    // Expect Flyn's ICR = (1 * 200) / 100 = 200%
    assert.isAtMost(th.getDifference(flyn_ICR, dec(2, 18)), 1000)

    // C opens with 2.5 ETH, 160 R
    await openPosition({ ICR: toBN(dec(3125, 15)), extraParams: { from: carol } })
    const carol_ICR = (await positionManager.getCurrentICR(carol, price)).toString()
    // Expect Carol's ICR = (2.5 * 200) / (160) = 312.50%
    assert.isAtMost(th.getDifference(carol_ICR, '3125000000000000000'), 1000)

    // D opens with 1 ETH, 0 R
    await openPosition({ ICR: toBN(dec(4, 18)), extraParams: { from: dennis } })
    const dennis_ICR = (await positionManager.getCurrentICR(dennis, price)).toString()
    // Expect Dennis's ICR = (1 * 200) / (50) = 400.00%
    assert.isAtMost(th.getDifference(dennis_ICR, dec(4, 18)), 1000)

    // E opens with 4405.45 ETH, 32598.35 R
    await openPosition({ ICR: toBN('27028668628933700000'), extraParams: { from: erin } })
    const erin_ICR = (await positionManager.getCurrentICR(erin, price)).toString()
    // Expect erin's ICR = (4405.45 * 200) / (32598.35) = 2702.87%
    assert.isAtMost(th.getDifference(erin_ICR, '27028668628933700000'), 100000)

    // H opens with 1 ETH, 180 R
    await openPosition({ ICR: toBN('1111111111111111111'), extraParams: { from: harriet } })
    const harriet_ICR = (await positionManager.getCurrentICR(harriet, price)).toString()
    // Expect Harriet's ICR = (1 * 200) / (180) = 111.11%
    assert.isAtMost(th.getDifference(harriet_ICR, '1111111111111111111'), 1000)
  })

  // --- Event emission in single liquidation ---

  // liquidatePositions - full redistribution
  it('liquidatePositions(): full redistribution. Compensates the correct amount, and liquidates the remainder', async () => {
    await priceFeed.setPrice(dec(1000, 18))

    await openPosition({ ICR: toBN(dec(200, 18)), extraParams: { from: whale } })

    // A-D open positions
    await openPosition({ ICR: toBN(dec(118, 16)), extraRAmount: dec(2000, 18), extraParams: { from: alice } })
    await openPosition({ ICR: toBN(dec(226, 16)), extraRAmount: dec(8000, 18), extraParams: { from: bob } })
    await openPosition({ ICR: toBN(dec(488, 16)), extraRAmount: dec(600, 18), extraParams: { from: carol } })
    await openPosition({ ICR: toBN(dec(445, 16)), extraRAmount: dec(1, 23), extraParams: { from: dennis } })

    // price drops to 200
    await priceFeed.setPrice(dec(200, 18))
    const price = await priceFeed.getPrice()

    // Check A, B, C, D have ICR < MCR
    assert.isTrue((await positionManager.getCurrentICR(alice, price)).lt(mv._MCR))
    assert.isTrue((await positionManager.getCurrentICR(bob, price)).lt(mv._MCR))
    assert.isTrue((await positionManager.getCurrentICR(carol, price)).lt(mv._MCR))
    assert.isTrue((await positionManager.getCurrentICR(dennis, price)).lt(mv._MCR))

    // --- Check value of of A's collateral is < $10, and value of B,C,D collateral are > $10  ---
    const aliceColl = (await positionManager.positions(alice))[1]
    const bobColl = (await positionManager.positions(bob))[1]
    const carolColl = (await positionManager.positions(carol))[1]
    const dennisColl = (await positionManager.positions(dennis))[1]

    // --- Check value of 0.5% of A, B, and C's collateral is <$10, and value of 0.5% of D's collateral is > $10 ---
    const _0pt5percent_aliceColl = aliceColl.div(web3.utils.toBN('200'))
    const _0pt5percent_bobColl = bobColl.div(web3.utils.toBN('200'))
    const _0pt5percent_carolColl = carolColl.div(web3.utils.toBN('200'))
    const _0pt5percent_dennisColl = dennisColl.div(web3.utils.toBN('200'))

    const collGasCompensation = await positionManagerTester.getCollGasCompensation(price)
    assert.equal(collGasCompensation, dec(1 , 18))

    /* Expect total gas compensation =
        0.5% of [A_coll + B_coll + C_coll + D_coll]
    */
    const expectedCollGasComp = _0pt5percent_aliceColl
          .add(_0pt5percent_bobColl)
          .add(_0pt5percent_carolColl)
          .add(_0pt5percent_dennisColl)

    // Liquidate positions A-D
    const liquidatorRBalance_before = web3.utils.toBN(await rToken.balanceOf(liquidator))
    const liquidatorCollBalance_before = web3.utils.toBN(await wstETHTokenMock.balanceOf(liquidator))
    await positionManager.batchLiquidatePositions([alice, bob, carol, dennis], { from: liquidator, gasPrice: GAS_PRICE })
    const liquidatorCollBalance_after = web3.utils.toBN(await wstETHTokenMock.balanceOf(liquidator))
    const liquidatorRBalance_after = web3.utils.toBN(await rToken.balanceOf(liquidator))

    // Check liquidator's balance has increased by the expected compensation amount

    const collCompensationReceived = (liquidatorCollBalance_after.sub(liquidatorCollBalance_before)).toString()
    const rCompensationReceived = (liquidatorRBalance_after.sub(liquidatorRBalance_before)).toString()

    const expectedRCompensation = toBN(dec(200, 18)).mul(toBN(4))

    assert.isAtMost(th.getDifference(expectedCollGasComp, collCompensationReceived), 1000)
    assert.isAtMost(th.getDifference(expectedRCompensation, rCompensationReceived), 1000)
  })

  // --- Position ordering by ICR tests ---

  it('Position ordering: same collateral, decreasing debt. Price successively increases. Positions should maintain ordering by ICR', async () => {
    const _10_accounts = accounts.slice(1, 11)
    await th.fillAccountsWithWstETH(contracts, _10_accounts)

    let debt = 50
    // create 10 positions, constant coll, descending debt 100 to 90 R
    for (const account of _10_accounts) {

      const debtString = debt.toString().concat('000000000000000000')
      await wstETHTokenMock.approve(positionManager.address, dec(30, 'ether'), { from: account})
      await openPosition({ extraRAmount: debtString, amount: dec(30, 'ether'), extraParams: { from: account } })

      const squeezedPositionAddr = th.squeezeAddr(account)

      debt -= 1
    }

    const initialPrice = await priceFeed.getPrice()
    const firstColl = (await positionManager.positions(_10_accounts[0]))[1]

    // Vary price 200-210
    let price = 200
    while (price < 210) {

      const priceString = price.toString().concat('000000000000000000')
      await priceFeed.setPrice(priceString)

      const ICRList = []
      const coll_firstPosition = (await positionManager.positions(_10_accounts[0]))[1]
      const gasComp_firstPosition = (await positionManagerTester.getCollGasCompensation(coll_firstPosition)).toString()

      for (account of _10_accounts) {
        // Check gas compensation is the same for all positions
        const coll = (await positionManager.positions(account))[1]
        const gasCompensation = (await positionManagerTester.getCollGasCompensation(coll)).toString()

        assert.equal(gasCompensation, gasComp_firstPosition)

        const ICR = await positionManager.getCurrentICR(account, price)
        ICRList.push(ICR)


        // Check position ordering by ICR is maintained
        if (ICRList.length > 1) {
          const prevICR = ICRList[ICRList.length - 2]

          try {
            assert.isTrue(ICR.gte(prevICR))
          } catch (error) {
            console.log(`ETH price at which position ordering breaks: ${price}`)
            logICRs(ICRList)
          }
        }

        price += 1
      }
    }
  })

  it('Position ordering: increasing collateral, constant debt. Price successively increases. Positions should maintain ordering by ICR', async () => {
    const _20_accounts = accounts.slice(1, 21)
    await th.fillAccountsWithWstETH(contracts, _20_accounts);

    let coll = 50
    // create 20 positions, increasing collateral, constant debt = 100R
    for (const account of _20_accounts) {

      const collString = coll.toString().concat('000000000000000000')
      await wstETHTokenMock.approve(positionManager.address, collString, { from: account})
      await openPosition({ extraRAmount: dec(100, 18), amount: collString, extraParams: { from: account } })

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
        const ICR = await positionManager.getCurrentICR(account, price)
        ICRList.push(ICR)

        // Check position ordering by ICR is maintained
        if (ICRList.length > 1) {
          const prevICR = ICRList[ICRList.length - 2]

          try {
            assert.isTrue(ICR.gte(prevICR))
          } catch (error) {
            console.log(`ETH price at which position ordering breaks: ${price}`)
            logICRs(ICRList)
          }
        }

        price += 10
      }
    }
  })

  it('Position ordering: Constant raw collateral ratio (excluding virtual debt). Price successively increases. Positions should maintain ordering by ICR', async () => {
    let collVals = [1, 5, 10, 25, 50, 100, 500, 1000, 5000, 10000, 50000, 100000, 500000, 1000000, 5000000].map(v => v * 20)
    const accountsList = accounts.slice(1, collVals.length + 1)
    await th.fillAccountsWithWstETH(contracts, accountsList)

    let accountIdx = 0
    for (const coll of collVals) {

      const debt = coll * 110

      const account = accountsList[accountIdx]
      const collString = coll.toString().concat('000000000000000000')
      await wstETHTokenMock.approve(positionManager.address, collString, { from: account})
      await openPosition({ extraRAmount: dec(100, 18), amount: collString, extraParams: { from: account } })

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
        const ICR = await positionManager.getCurrentICR(account, price)
        ICRList.push(ICR)

        // Check position ordering by ICR is maintained
        if (ICRList.length > 1) {
          const prevICR = ICRList[ICRList.length - 2]

          try {
            assert.isTrue(ICR.gte(prevICR))
          } catch (error) {
            console.log(error)
            console.log(`ETH price at which position ordering breaks: ${price}`)
            logICRs(ICRList)
          }
        }

        price += 10
      }
    }
  })
})

