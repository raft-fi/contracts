const { assert } = require("hardhat")
const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")

const th = testHelpers.TestHelper

const dec = th.dec
const toBN = th.toBN
const timeValues = testHelpers.TimeValues

const ZERO_ADDRESS = th.ZERO_ADDRESS
const assertRevert = th.assertRevert
const DEFAULT_PRICE = dec(200, 18);

/* NOTE: Some of the borrowing tests do not test for specific R fee values. They only test that the
 * fees are non-zero when they should occur, and that they decay over time.
 *
 * Specific R fee values will depend on the final fee schedule used, and the final choice for
 *  the parameter MINUTE_DECAY_FACTOR in the PositionManager, which is still TBD based on economic
 * modelling.
 *
 */

contract('BorrowerOperations', async accounts => {

  const [
    owner, alice, bob, carol, dennis, whale,
    A, B, C, D, E, F, G, H] = accounts;

  let priceFeed
  let rToken
  let positionManager
  let wstETHTokenMock

  let contracts

  const getOpenPositionRAmount = async (totalDebt) => th.getOpenPositionRAmount(contracts, totalDebt)
  const getNetBorrowingAmount = async (debtWithFee) => th.getNetBorrowingAmount(contracts, debtWithFee)
  const openPosition = async (params) => th.openPosition(contracts, params)
  const getPositionEntireColl = async (position) => th.getPositionEntireColl(contracts, position)
  const getPositionEntireDebt = async (position) => th.getPositionEntireDebt(contracts, position)
  const getActualDebtFromComposite = async (debt) => th.getActualDebtFromComposite(debt, contracts)
  const getPositionStake = async (position) => th.getPositionStake(contracts, position)

  let R_GAS_COMPENSATION
  let MIN_NET_DEBT
  let MCR

  before(async () => {

  })

  beforeEach(async () => {
      contracts = await deploymentHelper.deployLiquityCore(owner)

      priceFeed = contracts.priceFeedTestnet
      wstETHTokenMock = contracts.wstETHTokenMock
      rToken = contracts.rToken
      positionManager = contracts.positionManager

      R_GAS_COMPENSATION = await contracts.math.R_GAS_COMPENSATION()
      MIN_NET_DEBT = await contracts.math.MIN_NET_DEBT()
      MCR = await contracts.math.MCR()

      await th.fillAccountsWithWstETH(contracts, [
        owner, alice, bob, carol, dennis, whale,
        A, B, C, D, E, F, G, H
      ])
    })

    // it("addColl(), active Position: adds the right corrected stake after liquidations have occured", async () => {
    //  // TODO - check stake updates for addColl/withdrawColl/adustPosition ---

    //   // --- SETUP ---
    //   // A,B,C add 15/5/5 ETH, withdraw 100/100/900 R
    //   await openPosition(th._100pct, dec(100, 18), alice, alice, { from: alice, value: dec(15, 'ether') })
    //   await openPosition(th._100pct, dec(100, 18), bob, bob, { from: bob, value: dec(4, 'ether') })
    //   await openPosition(th._100pct, dec(900, 18), carol, carol, { from: carol, value: dec(5, 'ether') })

    //   await openPosition(th._100pct, 0, dennis, dennis, { from: dennis, value: dec(1, 'ether') })
    //   // --- TEST ---

    //   // price drops to 1ETH:100R, reducing Carol's ICR below MCR
    //   await priceFeed.setPrice('100000000000000000000');

    //   // close Carol's Position, liquidating her 5 ether and 900R.
    //   await positionManager.liquidate(carol, { from: owner });

    //   // dennis tops up his position by 1 ETH
    //   await positionManager.addColl(dennis, dennis, { from: dennis, value: dec(1, 'ether') })

    //   /* Check that Dennis's recorded stake is the right corrected stake, less than his collateral. A corrected
    //   stake is given by the formula:

    //   s = totalStakesSnapshot / totalCollateralSnapshot

    //   where snapshots are the values immediately after the last liquidation.  After Carol's liquidation,
    //   the ETH from her Position has now become the totalPendingETHReward. So:

    //   totalStakes = (alice_Stake + bob_Stake + dennis_orig_stake ) = (15 + 4 + 1) =  20 ETH.
    //   totalCollateral = (alice_Collateral + bob_Collateral + dennis_orig_coll + totalPendingETHReward) = (15 + 4 + 1 + 5)  = 25 ETH.

    //   Therefore, as Dennis adds 1 ether collateral, his corrected stake should be:  s = 2 * (20 / 25 ) = 1.6 ETH */
    //   const dennis_Position = await positionManager.positions(dennis)

    //   const dennis_Stake = dennis_Position[2]
    //   console.log(dennis_Stake.toString())

    //   assert.isAtMost(th.getDifference(dennis_Stake), 100)
    // })

    // --- withdrawR() ---

    it("withdrawR(): reverts when withdrawal would leave position with ICR < MCR", async () => {
      // alice creates a Position and adds first collateral
      await openPosition({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: bob } })

      // Price drops
      await priceFeed.setPrice(dec(100, 18))
      const price = await priceFeed.getPrice()

      assert.isTrue((await positionManager.getCurrentICR(alice, price)).lt(toBN(dec(110, 16))))

      const Rwithdrawal = 1  // withdraw 1 wei R

     await assertRevert(positionManager.managePosition(0, false, Rwithdrawal, true, alice, alice, th._100pct, { from: alice }),
      "BorrowerOps: An operation that would result in ICR < MCR is not permitted")
    })

    it("withdrawR(): decays a non-zero base rate", async () => {
      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      await openPosition({ extraRAmount: toBN(dec(20, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(20, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(20, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
      await openPosition({ extraRAmount: toBN(dec(20, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      const A_RBal = await rToken.balanceOf(A)

      // Artificially set base rate to 5%
      await positionManager.setBaseRate(dec(5, 16))

      // Check baseRate is now non-zero
      const baseRate_1 = await positionManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D withdraws R
      await positionManager.managePosition(0, false, dec(1, 18), true, A, A, th._100pct, { from: D })

      // Check baseRate has decreased
      const baseRate_2 = await positionManager.baseRate()
      assert.isTrue(baseRate_2.lt(baseRate_1))

      // 1 hour passes
      th.fastForwardTime(3600, web3.currentProvider)

      // E withdraws R
      await positionManager.managePosition(0, false, dec(1, 18), true, A, A, th._100pct, { from: E })

      const baseRate_3 = await positionManager.baseRate()
      assert.isTrue(baseRate_3.lt(baseRate_2))
    })

    it("withdrawR(): reverts if max fee > 100%", async () => {
      await openPosition({ extraRAmount: toBN(dec(10, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(20, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openPosition({ extraRAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      await assertRevert(positionManager.managePosition(0, false, dec(1, 18), true, A, A, dec(2, 18), { from: A }), "Max fee percentage must be between 0% and 100%")
      await assertRevert(positionManager.managePosition(0, false, dec(1, 18), true, A, A, '1000000000000000001', { from: A }), "Max fee percentage must be between 0% and 100%")
    })

    it("withdrawR(): reverts if fee exceeds max fee percentage", async () => {
      await openPosition({ extraRAmount: toBN(dec(60, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(60, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(70, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openPosition({ extraRAmount: toBN(dec(80, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
      await openPosition({ extraRAmount: toBN(dec(180, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      const totalSupply = await rToken.totalSupply()

      // Artificially make baseRate 5%
      await positionManager.setBaseRate(dec(5, 16))
      await positionManager.setLastFeeOpTimeToNow()

      let baseRate = await positionManager.baseRate() // expect 5% base rate
      assert.equal(baseRate, dec(5, 16))

      // 100%: 1e18,  10%: 1e17,  1%: 1e16,  0.1%: 1e15
      // 5%: 5e16
      // 0.5%: 5e15
      // actual: 0.5%, 5e15


      // rFee:                  15000000558793542
      // absolute _fee:            15000000558793542
      // actual feePercentage:      5000000186264514
      // user's _maxFeePercentage: 49999999999999999

      const lessThan5pct = '49999999999999999'
      await assertRevert(positionManager.managePosition(0, false, dec(3, 18), true, A, A, lessThan5pct, { from: A }), "Fee exceeded provided maximum")

      baseRate = await positionManager.baseRate() // expect 5% base rate
      assert.equal(baseRate, dec(5, 16))
      // Attempt with maxFee 1%
      await assertRevert(positionManager.managePosition(0, false, dec(1, 18), true, A, A, dec(1, 16), { from: B }), "Fee exceeded provided maximum")

      baseRate = await positionManager.baseRate()  // expect 5% base rate
      assert.equal(baseRate, dec(5, 16))
      // Attempt with maxFee 3.754%
      await assertRevert(positionManager.managePosition(0, false, dec(1, 18), true, A, A, dec(3754, 13), { from: C }), "Fee exceeded provided maximum")

      baseRate = await positionManager.baseRate()  // expect 5% base rate
      assert.equal(baseRate, dec(5, 16))
      // Attempt with maxFee 0.5%%
      await assertRevert(positionManager.managePosition(0, false, dec(1, 18), true, A, A, dec(5, 15), { from: D }), "Fee exceeded provided maximum")
    })

    it("withdrawR(): succeeds when fee is less than max fee percentage", async () => {
      await openPosition({ extraRAmount: toBN(dec(60, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(60, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(70, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openPosition({ extraRAmount: toBN(dec(80, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
      await openPosition({ extraRAmount: toBN(dec(180, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      const totalSupply = await rToken.totalSupply()

      // Artificially make baseRate 5%
      await positionManager.setBaseRate(dec(5, 16))
      await positionManager.setLastFeeOpTimeToNow()

      let baseRate = await positionManager.baseRate() // expect 5% base rate
      assert.isTrue(baseRate.eq(toBN(dec(5, 16))))

      // Attempt with maxFee > 5%
      const moreThan5pct = '50000000000000001'
      const tx1 = await positionManager.managePosition(0, false, dec(1, 18), true, A, A, moreThan5pct, { from: A })
      assert.isTrue(tx1.receipt.status)

      baseRate = await positionManager.baseRate() // expect 5% base rate
      assert.equal(baseRate, dec(5, 16))

      // Attempt with maxFee = 5%
      const tx2 = await positionManager.managePosition(0, false, dec(1, 18), true, A, A, dec(5, 16), { from: B })
      assert.isTrue(tx2.receipt.status)

      baseRate = await positionManager.baseRate() // expect 5% base rate
      assert.equal(baseRate, dec(5, 16))

      // Attempt with maxFee 10%
      const tx3 = await positionManager.managePosition(0, false, dec(1, 18), true, A, A, dec(1, 17), { from: C })
      assert.isTrue(tx3.receipt.status)

      baseRate = await positionManager.baseRate() // expect 5% base rate
      assert.equal(baseRate, dec(5, 16))

      // Attempt with maxFee 37.659%
      const tx4 = await positionManager.managePosition(0, false, dec(1, 18), true, A, A, dec(37659, 13), { from: D })
      assert.isTrue(tx4.receipt.status)

      // Attempt with maxFee 100%
      const tx5 = await positionManager.managePosition(0, false, dec(1, 18), true, A, A, dec(1, 18), { from: E })
      assert.isTrue(tx5.receipt.status)
    })

    it("withdrawR(): doesn't change base rate if it is already zero", async () => {
      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      await openPosition({ extraRAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      // Check baseRate is zero
      const baseRate_1 = await positionManager.baseRate()
      assert.equal(baseRate_1, '0')

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D withdraws R
      await positionManager.managePosition(0, false, dec(37, 18), true, A, A, th._100pct, { from: D })

      // Check baseRate is still 0
      const baseRate_2 = await positionManager.baseRate()
      assert.equal(baseRate_2, '0')

      // 1 hour passes
      th.fastForwardTime(3600, web3.currentProvider)

      // E opens position
      await positionManager.managePosition(0, false, dec(12, 18), true, A, A, th._100pct, { from: E })

      const baseRate_3 = await positionManager.baseRate()
      assert.equal(baseRate_3, '0')
    })

    it("withdrawR(): lastFeeOpTime doesn't update if less time than decay interval has passed since the last fee operation", async () => {
      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      await openPosition({ extraRAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await positionManager.setBaseRate(dec(5, 16))
      await positionManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await positionManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      const lastFeeOpTime_1 = await positionManager.lastFeeOperationTime()

      // 10 seconds pass
      th.fastForwardTime(10, web3.currentProvider)

      // Borrower C triggers a fee
      await positionManager.managePosition(0, false, dec(1, 18), true, C, C, th._100pct, { from: C })

      const lastFeeOpTime_2 = await positionManager.lastFeeOperationTime()

      // Check that the last fee operation time did not update, as borrower D's debt issuance occured
      // since before minimum interval had passed
      assert.isTrue(lastFeeOpTime_2.eq(lastFeeOpTime_1))

      // 60 seconds passes
      th.fastForwardTime(60, web3.currentProvider)

      // Check that now, at least one minute has passed since lastFeeOpTime_1
      const timeNow = await th.getLatestBlockTimestamp(web3)
      assert.isTrue(toBN(timeNow).sub(lastFeeOpTime_1).gte(60))

      // Borrower C triggers a fee
      await positionManager.managePosition(0, false, dec(1, 18), true, C, C, th._100pct, { from: C })

      const lastFeeOpTime_3 = await positionManager.lastFeeOperationTime()

      // Check that the last fee operation time DID update, as borrower's debt issuance occured
      // after minimum interval had passed
      assert.isTrue(lastFeeOpTime_3.gt(lastFeeOpTime_1))
    })


    it("withdrawR(): borrower can't grief the baseRate and stop it decaying by issuing debt at higher frequency than the decay granularity", async () => {
      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await positionManager.setBaseRate(dec(5, 16))
      await positionManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await positionManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 30 seconds pass
      th.fastForwardTime(30, web3.currentProvider)

      // Borrower C triggers a fee, before decay interval has passed
      await positionManager.managePosition(0, false, dec(1, 18), true, C, C, th._100pct, { from: C })

      // 30 seconds pass
      th.fastForwardTime(30, web3.currentProvider)

      // Borrower C triggers another fee
      await positionManager.managePosition(0, false, dec(1, 18), true, C, C, th._100pct, { from: C })

      // Check base rate has decreased even though Borrower tried to stop it decaying
      const baseRate_2 = await positionManager.baseRate()
      assert.isTrue(baseRate_2.lt(baseRate_1))
    })

    it("withdrawR(): borrowing at non-zero base rate sends R fee to fee recipient", async () => {
      const feeRecipient = await positionManager.feeRecipient()

      // time fast-forwards 1 year
      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

      const feeRecipient_RBalance_Before = await rToken.balanceOf(feeRecipient)

      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Artificially make baseRate 5%
      await positionManager.setBaseRate(dec(5, 16))
      await positionManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await positionManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D withdraws R
      await positionManager.managePosition(0, false, dec(37, 18), true, C, C, th._100pct, { from: D })

      // Check feeRecipient R balance after has increased
      const feeRecipient_RBalance_After = await rToken.balanceOf(feeRecipient)
      assert.isTrue(feeRecipient_RBalance_After.gt(feeRecipient_RBalance_Before))
    })

    it("withdrawR(): borrowing at non-zero base records the (drawn debt + fee) on the Position struct", async () => {
      // time fast-forwards 1 year
      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
      const D_debtBefore = await getPositionEntireDebt(D)

      // Artificially make baseRate 5%
      await positionManager.setBaseRate(dec(5, 16))
      await positionManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await positionManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D withdraws R
      const withdrawal_D = toBN(dec(37, 18))
      const withdrawalTx = await positionManager.managePosition(0, false, toBN(dec(37, 18)), true, D, D, th._100pct, { from: D })

      const emittedFee = toBN(th.getRfeeFromRBorrowingEvent(withdrawalTx))
      assert.isTrue(emittedFee.gt(toBN('0')))

      const newDebt = (await positionManager.positions(D))[0]

      // Check debt on Position struct equals initial debt + withdrawal + emitted fee
      th.assertIsApproximatelyEqual(newDebt, D_debtBefore.add(withdrawal_D).add(emittedFee), 10000)
    })

    it("withdrawR(): Borrowing at non-zero base rate sends requested amount to the user", async () => {
      const feeRecipient = await positionManager.feeRecipient()

      // time fast-forwards 1 year
      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

      // Check feeRecipient Staking contract balance before == 0
      const feeRecipient_RBalance_Before = await rToken.balanceOf(feeRecipient)
      assert.equal(feeRecipient_RBalance_Before, '0')

      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Artificially make baseRate 5%
      await positionManager.setBaseRate(dec(5, 16))
      await positionManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await positionManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      const D_RBalanceBefore = await rToken.balanceOf(D)

      // D withdraws R
      const D_RRequest = toBN(dec(37, 18))
      await positionManager.managePosition(0, false, D_RRequest, true, D, D, th._100pct, { from: D })

      // Check fee recipient's R balance has increased
      const feeRecipient_RBalance_After = await rToken.balanceOf(feeRecipient)
      assert.isTrue(feeRecipient_RBalance_After.gt(feeRecipient_RBalance_Before))

      // Check D's R balance now equals their initial balance plus request R
      const D_RBalanceAfter = await rToken.balanceOf(D)
      assert.isTrue(D_RBalanceAfter.eq(D_RBalanceBefore.add(D_RRequest)))
    })

    it("withdrawR(): Borrowing at zero base rate sends debt request to user", async () => {
      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check baseRate is zero
      const baseRate_1 = await positionManager.baseRate()
      assert.equal(baseRate_1, '0')

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      const D_RBalanceBefore = await rToken.balanceOf(D)

      // D withdraws R
      const D_RRequest = toBN(dec(37, 18))
      await positionManager.managePosition(0, false, dec(37, 18), true, D, D, th._100pct, { from: D })

      // Check D's R balance now equals their requested R
      const D_RBalanceAfter = await rToken.balanceOf(D)

      // Check D's position debt == D's R balance + liquidation reserve
      assert.isTrue(D_RBalanceAfter.eq(D_RBalanceBefore.add(D_RRequest)))
    })

    it("withdrawR(): reverts when calling address does not have active position", async () => {
      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: alice } })
      await openPosition({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      // Bob successfully withdraws R
      const txBob = await positionManager.managePosition(0, false, dec(100, 18), true, bob, bob, th._100pct, { from: bob })
      assert.isTrue(txBob.receipt.status)

      // Carol with no active position attempts to withdraw R
      try {
        const txCarol = await positionManager.managePosition(0, false, dec(100, 18), true, carol, carol, th._100pct, { from: carol })
        assert.isFalse(txCarol.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("withdrawR(): reverts when requested withdrawal amount is zero R", async () => {
      await openPosition({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openPosition({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      // Bob successfully withdraws 1e-18 R
      const txBob = await positionManager.managePosition(0, false, 1, true, bob, bob, th._100pct, { from: bob })
      assert.isTrue(txBob.receipt.status)

      // Alice attempts to withdraw 0 R
      try {
        const txAlice = await positionManager.managePosition(0, false, 0, true, alice, alice, th._100pct, { from: alice })
        assert.isFalse(txAlice.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("withdrawR(): reverts when withdrawal would bring the position's ICR < MCR", async () => {
      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: alice } })
      await openPosition({ ICR: toBN(dec(11, 17)), extraParams: { from: bob } })

      // Bob tries to withdraw R that would bring his ICR < MCR
      try {
        const txBob = await positionManager.managePosition(0, false, 1, true, bob, bob, th._100pct, { from: bob })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("withdrawR(): increases the Position's R debt by the correct amount", async () => {
      await openPosition({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      // check before
      const aliceDebtBefore = await getPositionEntireDebt(alice)
      assert.isTrue(aliceDebtBefore.gt(toBN(0)))

      await positionManager.managePosition(0, false, await getNetBorrowingAmount(100), true, alice, alice, th._100pct, { from: alice })

      // check after
      const aliceDebtAfter = await getPositionEntireDebt(alice)
      th.assertIsApproximatelyEqual(aliceDebtAfter, aliceDebtBefore.add(toBN(100)))
    })

    it("withdrawR(): increases user RToken balance by correct amount", async () => {
      await wstETHTokenMock.approve(positionManager.address, toBN(dec(100, 'ether')), { from: alice})
      await openPosition({ amount: toBN(dec(100, 'ether')), extraParams: { from: alice } })

      // check before
      const alice_RTokenBalance_Before = await rToken.balanceOf(alice)
      assert.isTrue(alice_RTokenBalance_Before.gt(toBN('0')))

      await positionManager.managePosition(0, false, dec(10000, 18), true, alice, alice, th._100pct, { from: alice })

      // check after
      const alice_RTokenBalance_After = await rToken.balanceOf(alice)
      assert.isTrue(alice_RTokenBalance_After.eq(alice_RTokenBalance_Before.add(toBN(dec(10000, 18)))))
    })

    // --- adjustPosition() ---

    it("adjustPosition(): Reverts if repaid amount is greater than current debt", async () => {
      const { totalDebt } = await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })
      const repayAmount = totalDebt.sub(R_GAS_COMPENSATION).add(toBN(1))
      await openPosition({ extraRAmount: repayAmount, ICR: toBN(dec(150, 16)), extraParams: { from: bob } })

      await rToken.transfer(alice, repayAmount, { from: bob })

      await assertRevert(positionManager.managePosition(0, false, repayAmount, false, alice, alice, th._100pct, { from: alice }),
                         "ERC20: transfer amount exceeds balance")
    })

    it("adjustPosition(): reverts when adjustment would leave position with ICR < MCR", async () => {
      // alice creates a Position and adds first collateral
      await openPosition({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: bob } })

      // Price drops
      await priceFeed.setPrice(dec(100, 18))
      const price = await priceFeed.getPrice()

      assert.isTrue((await positionManager.getCurrentICR(alice, price)).lt(toBN(dec(110, 16))))

      const RRepayment = 1  // 1 wei repayment
      const collTopUp = 1

      await wstETHTokenMock.approve(positionManager.address, collTopUp, { from: alice})
      await assertRevert(positionManager.managePosition(collTopUp, true, RRepayment, false, alice, alice, th._100pct, { from: alice }),
        "BorrowerOps: An operation that would result in ICR < MCR is not permitted")
    })

    it("adjustPosition(): reverts if max fee < borrowing spread", async () => {
      await positionManager.setBorrowingSpread(toBN(dec(5, 15)), { from: owner })

      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })

      await wstETHTokenMock.approve(positionManager.address, dec(2, 16), { from: A})
      await assertRevert(positionManager.managePosition(dec(2, 16), true, dec(1, 18), true, A, A, 0, { from: A }), "Max fee percentage must be between borrowing spread and 100%")
      await wstETHTokenMock.approve(positionManager.address, dec(2, 16), { from: A})
      await assertRevert(positionManager.managePosition(dec(2, 16), true, dec(1, 18), true, A, A, 1, { from: A }), "Max fee percentage must be between borrowing spread and 100%")
      await wstETHTokenMock.approve(positionManager.address, dec(2, 16), { from: A})
      await assertRevert(positionManager.managePosition(dec(2, 16), true, dec(1, 18), true, A, A, '4999999999999999', { from: A }), "Max fee percentage must be between borrowing spread and 100%")
    })

    it("adjustPosition(): decays a non-zero base rate", async () => {
      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openPosition({ extraRAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      // Artificially make baseRate 5%
      await positionManager.setBaseRate(dec(5, 16))
      await positionManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await positionManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D adjusts position
      await positionManager.managePosition(0, false, dec(37, 18), true, D, D, th._100pct, { from: D })

      // Check baseRate has decreased
      const baseRate_2 = await positionManager.baseRate()
      assert.isTrue(baseRate_2.lt(baseRate_1))

      // 1 hour passes
      th.fastForwardTime(3600, web3.currentProvider)

      // E adjusts position
      await positionManager.managePosition(0, false, dec(37, 15), true, E, E, th._100pct, { from: D })

      const baseRate_3 = await positionManager.baseRate()
      assert.isTrue(baseRate_3.lt(baseRate_2))
    })

    it("adjustPosition(): doesn't decay a non-zero base rate when user issues 0 debt", async () => {
      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await positionManager.setBaseRate(dec(5, 16))
      await positionManager.setLastFeeOpTimeToNow()

      // D opens position
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check baseRate is now non-zero
      const baseRate_1 = await positionManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D adjusts position with 0 debt
      await wstETHTokenMock.approve(positionManager.address, dec(1, 'ether'), { from: D})
      await positionManager.managePosition(dec(1, 'ether'), true, 0, false, D, D, th._100pct, { from: D })

      // Check baseRate has not decreased
      const baseRate_2 = await positionManager.baseRate()
      assert.isTrue(baseRate_2.eq(baseRate_1))
    })

    it("adjustPosition(): doesn't change base rate if it is already zero", async () => {
      await openPosition({ extraRAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check baseRate is zero
      const baseRate_1 = await positionManager.baseRate()
      assert.equal(baseRate_1, '0')

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D adjusts position
      await positionManager.managePosition(0, false, dec(37, 18), true, D, D, th._100pct, { from: D })

      // Check baseRate is still 0
      const baseRate_2 = await positionManager.baseRate()
      assert.equal(baseRate_2, '0')

      // 1 hour passes
      th.fastForwardTime(3600, web3.currentProvider)

      // E adjusts position
      await positionManager.managePosition(0, false, dec(37, 15), true, E, E, th._100pct, { from: D })

      const baseRate_3 = await positionManager.baseRate()
      assert.equal(baseRate_3, '0')
    })

    it("adjustPosition(): lastFeeOpTime doesn't update if less time than decay interval has passed since the last fee operation", async () => {
      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await positionManager.setBaseRate(dec(5, 16))
      await positionManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await positionManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      const lastFeeOpTime_1 = await positionManager.lastFeeOperationTime()

      // 10 seconds pass
      th.fastForwardTime(10, web3.currentProvider)

      // Borrower C triggers a fee
      await positionManager.managePosition(0, false, dec(1, 18), true, C, C, th._100pct, { from: C })

      const lastFeeOpTime_2 = await positionManager.lastFeeOperationTime()

      // Check that the last fee operation time did not update, as borrower D's debt issuance occured
      // since before minimum interval had passed
      assert.isTrue(lastFeeOpTime_2.eq(lastFeeOpTime_1))

      // 60 seconds passes
      th.fastForwardTime(60, web3.currentProvider)

      // Check that now, at least one minute has passed since lastFeeOpTime_1
      const timeNow = await th.getLatestBlockTimestamp(web3)
      assert.isTrue(toBN(timeNow).sub(lastFeeOpTime_1).gte(60))

      // Borrower C triggers a fee
      await positionManager.managePosition(0, false, dec(1, 18), true, C, C, th._100pct, { from: C })

      const lastFeeOpTime_3 = await positionManager.lastFeeOperationTime()

      // Check that the last fee operation time DID update, as borrower's debt issuance occured
      // after minimum interval had passed
      assert.isTrue(lastFeeOpTime_3.gt(lastFeeOpTime_1))
    })

    it("adjustPosition(): borrower can't grief the baseRate and stop it decaying by issuing debt at higher frequency than the decay granularity", async () => {
      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await positionManager.setBaseRate(dec(5, 16))
      await positionManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await positionManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // Borrower C triggers a fee, before decay interval of 1 minute has passed
      await positionManager.managePosition(0, false, dec(1, 18), true, C, C, th._100pct, { from: C })

      // 1 minute passes
      th.fastForwardTime(60, web3.currentProvider)

      // Borrower C triggers another fee
      await positionManager.managePosition(0, false, dec(1, 18), true, C, C, th._100pct, { from: C })

      // Check base rate has decreased even though Borrower tried to stop it decaying
      const baseRate_2 = await positionManager.baseRate()
      assert.isTrue(baseRate_2.lt(baseRate_1))
    })

    it("adjustPosition(): borrowing at non-zero base rate sends R fee to fee recipient", async () => {
      const feeRecipient = await positionManager.feeRecipient()

      // time fast-forwards 1 year
      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

      // Check feeRecipient R balance before == 0
      const feeRecipient_RBalance_Before = await rToken.balanceOf(feeRecipient)
      assert.equal(feeRecipient_RBalance_Before, '0')

      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await positionManager.setBaseRate(dec(5, 16))
      await positionManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await positionManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D adjusts position
      await openPosition({ extraRAmount: toBN(dec(37, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check feeRecipient R balance after has increased
      const feeRecipient_RBalance_After = await rToken.balanceOf(feeRecipient)
      assert.isTrue(feeRecipient_RBalance_After.gt(feeRecipient_RBalance_Before))
    })

    it("adjustPosition(): borrowing at non-zero base records the (drawn debt + fee) on the Position struct", async () => {
      // time fast-forwards 1 year
      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
      const D_debtBefore = await getPositionEntireDebt(D)

      // Artificially make baseRate 5%
      await positionManager.setBaseRate(dec(5, 16))
      await positionManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await positionManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      const withdrawal_D = toBN(dec(37, 18))

      // D withdraws R
      const adjustmentTx = await positionManager.managePosition(0, false, withdrawal_D, true, D, D, th._100pct, { from: D })

      const emittedFee = toBN(th.getRfeeFromRBorrowingEvent(adjustmentTx))
      assert.isTrue(emittedFee.gt(toBN('0')))

      const D_newDebt = (await positionManager.positions(D))[0]

      // Check debt on Position struct equals initila debt plus drawn debt plus emitted fee
      assert.isTrue(D_newDebt.eq(D_debtBefore.add(withdrawal_D).add(emittedFee)))
    })

    it("adjustPosition(): Borrowing at non-zero base rate sends requested amount to the user", async () => {
      const feeRecipient = await positionManager.feeRecipient()

      // time fast-forwards 1 year
      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

      // Check feeRecipient Staking contract balance before == 0
      const feeRecipient_RBalance_Before = await rToken.balanceOf(feeRecipient)
      assert.equal(feeRecipient_RBalance_Before, '0')

      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      const D_RBalanceBefore = await rToken.balanceOf(D)

      // Artificially make baseRate 5%
      await positionManager.setBaseRate(dec(5, 16))
      await positionManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await positionManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D adjusts position
      const RRequest_D = toBN(dec(40, 18))
      await positionManager.managePosition(0, false, RRequest_D, true, D, D, th._100pct, { from: D })

      // Check fee recipient's R balance has increased
      const feeRecipient_RBalance_After = await rToken.balanceOf(feeRecipient)
      assert.isTrue(feeRecipient_RBalance_After.gt(feeRecipient_RBalance_Before))

      // Check D's R balance has increased by their requested R
      const D_RBalanceAfter = await rToken.balanceOf(D)
      assert.isTrue(D_RBalanceAfter.eq(D_RBalanceBefore.add(RRequest_D)))
    })

    it("adjustPosition(): Borrowing at zero rate doesn't change R balance of feeRecipient", async () => {
      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check baseRate is zero
      const baseRate_1 = await positionManager.baseRate()
      assert.equal(baseRate_1, '0')

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // Check staking R balance before > 0
      const feeRecipient = await positionManager.feeRecipient()
      const feeRecipient_RBalance_Before = await rToken.balanceOf(feeRecipient)
      assert.isTrue(feeRecipient_RBalance_Before.eq(toBN('0')))

      // D adjusts position
      await positionManager.managePosition(0, true, dec(37, 18), true, D, D, th._100pct, { from: D })

      // Check staking R balance after > staking balance before
      const feeRecipient_RBalance_After = await rToken.balanceOf(feeRecipient)
      assert.isTrue(feeRecipient_RBalance_After.eq(feeRecipient_RBalance_Before))
    })

    it("adjustPosition(): Borrowing at non-zero rate changes R balance of fee recipient", async () => {
      const feeRecipient = await positionManager.feeRecipient()

      await positionManager.setBorrowingSpread(dec(5, 15), { from: owner })

      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(30, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(40, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openPosition({ extraRAmount: toBN(dec(50, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check baseRate is zero
      const baseRate_1 = await positionManager.baseRate()
      assert.equal(baseRate_1, '0')

      // Check if borrowing rate > 0
      const borrowingRate = await positionManager.getBorrowingRate()
      assert.isTrue(borrowingRate.gt(toBN(0)))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // Check staking R balance before > 0
      const feeRecipient_RBalance_Before = await rToken.balanceOf(feeRecipient)
      assert.isTrue(feeRecipient_RBalance_Before.gt(toBN('0')))

      // D adjusts position
      await positionManager.managePosition(0, true, dec(37, 18), true, D, D, th._100pct, { from: D })

      // Check staking R balance after > staking balance before
      const feeRecipient_RBalance_After = await rToken.balanceOf(feeRecipient)
      assert.isTrue(feeRecipient_RBalance_After.gt(feeRecipient_RBalance_Before))
    })

    it("adjustPosition(): Borrowing at zero base rate sends total requested R to the user", async () => {
      await wstETHTokenMock.approve(positionManager.address, toBN(dec(100, 'ether')) , { from: whale})
      await openPosition({ extraRAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), amount: toBN(dec(100, 'ether')), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openPosition({ extraRAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      const D_RBalBefore = await rToken.balanceOf(D)
      // Check baseRate is zero
      const baseRate_1 = await positionManager.baseRate()
      assert.equal(baseRate_1, '0')

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      const DUSDBalanceBefore = await rToken.balanceOf(D)

      // D adjusts position
      const RRequest_D = toBN(dec(40, 18))
      await positionManager.managePosition(0, false, RRequest_D, true, D, D, th._100pct, { from: D })

      // Check D's R balance increased by their requested R
      const RBalanceAfter = await rToken.balanceOf(D)
      assert.isTrue(RBalanceAfter.eq(D_RBalBefore.add(RRequest_D)))
    })

    it("adjustPosition(): reverts when calling address has no active position", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openPosition({ extraRAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      // Alice coll and debt increase(+1 ETH, +50R)
      await wstETHTokenMock.approve(positionManager.address, dec(1, 'ether'), { from: alice})
      await positionManager.managePosition(dec(1, 'ether'), false, dec(50, 18), true, alice, alice, th._100pct, { from: alice })

      try {
        await wstETHTokenMock.approve(positionManager.address, dec(1, 'ether'), { from: carol})
        const txCarol = await positionManager.managePosition(dec(1, 'ether'), false, dec(50, 18), true, carol, carol, th._100pct, { from: carol })
        assert.isFalse(txCarol.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("adjustPosition(): reverts when R repaid is > debt of the position", async () => {
      await openPosition({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openPosition({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      const bobDebt = await getPositionEntireDebt(bob)
      assert.isTrue(bobDebt.gt(toBN('0')))

      const remainingDebt = (await positionManager.positions(bob))[0].sub(R_GAS_COMPENSATION)

      // Bob attempts an adjustment that would repay 1 wei more than his debt
      await wstETHTokenMock.approve(positionManager.address, dec(1, 'ether'), { from: bob})
      await assertRevert(
        positionManager.managePosition(dec(1, 'ether'), true, remainingDebt.add(toBN(1)), false, bob, bob, th._100pct, { from: bob }),
        "revert"
      )
    })

    it("adjustPosition(): reverts when attempted ETH withdrawal is >= the position's collateral", async () => {
      await openPosition({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openPosition({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })
      await openPosition({ ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

      const carolColl = await getPositionEntireColl(carol)

      // Carol attempts an adjustment that would withdraw 1 wei more than her ETH
      try {
        const txCarol = await positionManager.managePosition(carolColl.add(toBN(1)), false, 0, true, carol, carol, th._100pct, { from: carol })
        assert.isFalse(txCarol.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("adjustPosition(): reverts when change would cause the ICR of the position to fall below the MCR", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

      await priceFeed.setPrice(dec(100, 18))

      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(11, 17)), extraParams: { from: alice } })
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(11, 17)), extraParams: { from: bob } })

      // Bob attempts to increase debt by 100 R and 1 ether, i.e. a change that constitutes a 100% ratio of coll:debt.
      // Since his ICR prior is 110%, this change would reduce his ICR below MCR.
      try {
        await wstETHTokenMock.approve(positionManager.address, dec(1, 'ether'), { from: bob})
        const txBob = await positionManager.managePosition(dec(1, 'ether'), true, dec(100, 18), true, bob, bob, th._100pct, { from: bob })
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("adjustPosition(): With 0 coll change, doesn't change borrower's coll", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceCollBefore = await getPositionEntireColl(alice)

      assert.isTrue(aliceCollBefore.gt(toBN('0')))

      // Alice adjusts position. No coll change, and a debt increase (+50R)
      await positionManager.managePosition(0, false, dec(50, 18), true, alice, alice, th._100pct, { from: alice })

      const aliceCollAfter = await getPositionEntireColl(alice)

      assert.isTrue(aliceCollAfter.eq(aliceCollBefore))
    })

    it("adjustPosition(): With 0 debt change, doesn't change borrower's debt", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceDebtBefore = await getPositionEntireDebt(alice)

      assert.isTrue(aliceDebtBefore.gt(toBN('0')))

      // Alice adjusts position. Coll change, no debt change
      await wstETHTokenMock.approve(positionManager.address, dec(1, 'ether'), { from: alice})
      await positionManager.managePosition(dec(1, 'ether'), true, 0, false, alice, alice, th._100pct, { from: alice })

      const aliceDebtAfter = await getPositionEntireDebt(alice)

      assert.isTrue(aliceDebtAfter.eq(aliceDebtBefore))
    })

    it("adjustPosition(): updates borrower's debt and coll with an increase in both", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const debtBefore = await getPositionEntireDebt(alice)
      const collBefore = await getPositionEntireColl(alice)
      assert.isTrue(debtBefore.gt(toBN('0')))
      assert.isTrue(collBefore.gt(toBN('0')))

      // Alice adjusts position. Coll and debt increase(+1 ETH, +50R)
      await wstETHTokenMock.approve(positionManager.address, dec(1, 'ether'), { from: alice})
      await positionManager.managePosition(dec(1, 'ether'), true, await getNetBorrowingAmount(dec(50, 18)), true, alice, alice, th._100pct, { from: alice })

      const debtAfter = await getPositionEntireDebt(alice)
      const collAfter = await getPositionEntireColl(alice)

      th.assertIsApproximatelyEqual(debtAfter, debtBefore.add(toBN(dec(50, 18))), 10000)
      th.assertIsApproximatelyEqual(collAfter, collBefore.add(toBN(dec(1, 18))), 10000)
    })

    it("adjustPosition(): updates borrower's debt and coll with a decrease in both", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const debtBefore = await getPositionEntireDebt(alice)
      const collBefore = await getPositionEntireColl(alice)
      assert.isTrue(debtBefore.gt(toBN('0')))
      assert.isTrue(collBefore.gt(toBN('0')))

      // Alice adjusts position coll and debt decrease (-0.5 ETH, -50R)
      await positionManager.managePosition(dec(500, 'finney'), false, dec(50, 18), false, alice, alice, th._100pct, { from: alice })

      const debtAfter = await getPositionEntireDebt(alice)
      const collAfter = await getPositionEntireColl(alice)

      assert.isTrue(debtAfter.eq(debtBefore.sub(toBN(dec(50, 18)))))
      assert.isTrue(collAfter.eq(collBefore.sub(toBN(dec(5, 17)))))
    })

    it("adjustPosition(): updates borrower's  debt and coll with coll increase, debt decrease", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const debtBefore = await getPositionEntireDebt(alice)
      const collBefore = await getPositionEntireColl(alice)
      assert.isTrue(debtBefore.gt(toBN('0')))
      assert.isTrue(collBefore.gt(toBN('0')))

      // Alice adjusts position - coll increase and debt decrease (+0.5 ETH, -50R)
      await wstETHTokenMock.approve(positionManager.address, dec(500, 'finney'), { from: alice})
      await positionManager.managePosition(dec(500, 'finney'), true, dec(50, 18), false, alice, alice, th._100pct, { from: alice })

      const debtAfter = await getPositionEntireDebt(alice)
      const collAfter = await getPositionEntireColl(alice)

      th.assertIsApproximatelyEqual(debtAfter, debtBefore.sub(toBN(dec(50, 18))), 10000)
      th.assertIsApproximatelyEqual(collAfter, collBefore.add(toBN(dec(5, 17))), 10000)
    })

    it("adjustPosition(): updates borrower's debt and coll with coll decrease, debt increase", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const debtBefore = await getPositionEntireDebt(alice)
      const collBefore = await getPositionEntireColl(alice)
      assert.isTrue(debtBefore.gt(toBN('0')))
      assert.isTrue(collBefore.gt(toBN('0')))

      // Alice adjusts position - coll decrease and debt increase (0.1 ETH, 10R)
      await positionManager.managePosition(dec(1, 17), false, await getNetBorrowingAmount(dec(1, 18)), true, alice, alice, th._100pct, { from: alice })

      const debtAfter = await getPositionEntireDebt(alice)
      const collAfter = await getPositionEntireColl(alice)

      th.assertIsApproximatelyEqual(debtAfter, debtBefore.add(toBN(dec(1, 18))), 10000)
      th.assertIsApproximatelyEqual(collAfter, collBefore.sub(toBN(dec(1, 17))), 10000)
    })

    it("adjustPosition(): updates borrower's stake and totalStakes with a coll increase", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const stakeBefore = (await positionManager.positions(alice))[2]
      const totalStakesBefore = await positionManager.totalStakes();
      assert.isTrue(stakeBefore.gt(toBN('0')))
      assert.isTrue(totalStakesBefore.gt(toBN('0')))

      // Alice adjusts position - coll and debt increase (+1 ETH, +50 R)
      await wstETHTokenMock.approve(positionManager.address, dec(1, 'ether'), { from: alice})
      await positionManager.managePosition(dec(1, 'ether'), true, dec(50, 18), true, alice, alice, th._100pct, { from: alice })

      const stakeAfter = (await positionManager.positions(alice))[2]
      const totalStakesAfter = await positionManager.totalStakes();

      assert.isTrue(stakeAfter.eq(stakeBefore.add(toBN(dec(1, 18)))))
      assert.isTrue(totalStakesAfter.eq(totalStakesBefore.add(toBN(dec(1, 18)))))
    })

    it("adjustPosition(): updates borrower's stake and totalStakes with a coll decrease", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const stakeBefore = (await positionManager.positions(alice))[2]
      const totalStakesBefore = await positionManager.totalStakes();
      assert.isTrue(stakeBefore.gt(toBN('0')))
      assert.isTrue(totalStakesBefore.gt(toBN('0')))

      // Alice adjusts position - coll decrease and debt decrease
      await positionManager.managePosition(dec(500, 'finney'), false, dec(50, 18), false, alice, alice, th._100pct, { from: alice })

      const stakeAfter = (await positionManager.positions(alice))[2]
      const totalStakesAfter = await positionManager.totalStakes();

      assert.isTrue(stakeAfter.eq(stakeBefore.sub(toBN(dec(5, 17)))))
      assert.isTrue(totalStakesAfter.eq(totalStakesBefore.sub(toBN(dec(5, 17)))))
    })

    it("adjustPosition(): changes RToken balance by the requested decrease", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const alice_RTokenBalance_Before = await rToken.balanceOf(alice)
      assert.isTrue(alice_RTokenBalance_Before.gt(toBN('0')))

      // Alice adjusts position - coll decrease and debt decrease
      await positionManager.managePosition(dec(100, 'finney'), false, dec(10, 18), false, alice, alice, th._100pct, { from: alice })

      // check after
      const alice_RTokenBalance_After = await rToken.balanceOf(alice)
      assert.isTrue(alice_RTokenBalance_After.eq(alice_RTokenBalance_Before.sub(toBN(dec(10, 18)))))
    })

    it("adjustPosition(): changes RToken balance by the requested increase", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const alice_RTokenBalance_Before = await rToken.balanceOf(alice)
      assert.isTrue(alice_RTokenBalance_Before.gt(toBN('0')))

      // Alice adjusts position - coll increase and debt increase
      await wstETHTokenMock.approve(positionManager.address, dec(1, 'ether'), { from: alice})
      await positionManager.managePosition(dec(1, 'ether'), true, dec(100, 18), true, alice, alice,  th._100pct, { from: alice })

      // check after
      const alice_RTokenBalance_After = await rToken.balanceOf(alice)
      assert.isTrue(alice_RTokenBalance_After.eq(alice_RTokenBalance_Before.add(toBN(dec(100, 18)))))
    })

    it("adjustPosition(): Changes the position manager's collateralToken and raw ether balance by the requested decrease", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const positionManager_RawEther_Before = toBN(await wstETHTokenMock.balanceOf(positionManager.address))
      assert.isTrue(positionManager_RawEther_Before.gt(toBN('0')))

      // Alice adjusts position - coll decrease and debt decrease
      await positionManager.managePosition(dec(100, 'finney'), false, dec(10, 18), false, alice, alice, th._100pct, { from: alice })

      const positionManager_RawEther_After = toBN(await wstETHTokenMock.balanceOf(positionManager.address))
      assert.isTrue(positionManager_RawEther_After.eq(positionManager_RawEther_Before.sub(toBN(dec(1, 17)))))
    })

    it("adjustPosition(): Changes the position manager's raw ether balance by the amount of ETH sent", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const positionManager_RawEther_Before = toBN(await wstETHTokenMock.balanceOf(positionManager.address))
      assert.isTrue(positionManager_RawEther_Before.gt(toBN('0')))

      // Alice adjusts position - coll increase and debt increase
      await wstETHTokenMock.approve(positionManager.address, dec(1, 'ether'), { from: alice})
      await positionManager.managePosition(dec(1, 'ether'), true, dec(100, 18), true, alice, alice, th._100pct, { from: alice })

      const positionManager_RawEther_After = toBN(await wstETHTokenMock.balanceOf(positionManager.address))
      assert.isTrue(positionManager_RawEther_After.eq(positionManager_RawEther_Before.add(toBN(dec(1, 18)))))
    })

    it("adjustPosition(): new coll = 0 and new debt = 0 is not allowed, as gas compensation still counts toward ICR", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })
      const aliceColl = await getPositionEntireColl(alice)
      const aliceDebt = await getPositionEntireColl(alice)
      const isInSortedList_Before = (await positionManager.sortedPositionsNodes(alice))[0]

      assert.isTrue(isInSortedList_Before)
      await assertRevert(
        positionManager.managePosition(aliceColl, false, aliceDebt, true, alice, alice, th._100pct, { from: alice }),
        'BorrowerOps: An operation that would result in ICR < MCR is not permitted'
      )
    })

    it("adjustPosition(): Reverts if requested debt increase and amount is zero", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      await assertRevert(positionManager.managePosition(0, false, 0, true, alice, alice, th._100pct, { from: alice }),
        'BorrowerOps: Debt increase requires non-zero debtChange')
    })

    it("adjustPosition(): Reverts if it’s zero adjustment", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      await assertRevert(positionManager.managePosition(0, false, 0, false, alice, alice, th._100pct, { from: alice }),
                         'BorrowerOps: There must be either a collateral change or a debt change')
    })

    it("adjustPosition(): Reverts if requested coll withdrawal is greater than position's collateral", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: alice } })

      const aliceColl = await getPositionEntireColl(alice)

      // Requested coll withdrawal > coll in the position
      await assertRevert(positionManager.managePosition(aliceColl.add(toBN(1)), false, 0, false, alice, alice, th._100pct, { from: alice }))
      await assertRevert(positionManager.managePosition(aliceColl.add(toBN(dec(37, 'ether'))), false, 0, true, bob, bob, th._100pct, { from: bob }))
    })

    it("adjustPosition(): Reverts if borrower has insufficient R balance to cover his debt repayment", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: B } })
      const bobDebt = await getPositionEntireDebt(B)

      // Bob transfers some R to carol
      await rToken.transfer(C, dec(10, 18), { from: B })

      //Confirm B's R balance is less than 50 R
      const B_RBal = await rToken.balanceOf(B)
      assert.isTrue(B_RBal.lt(bobDebt))

      const repayRPromise_B = positionManager.managePosition(0, true, bobDebt, false, B, B, th._100pct, { from: B })

      // B attempts to repay all his debt
      await assertRevert(repayRPromise_B, "revert")
    })

    // --- closePosition() ---

    it.skip("closePosition(): reverts when position is the only one in the system", async () => {
      await openPosition({ extraRAmount: toBN(dec(100000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      // Artificially mint to Alice so she has enough to close her position
      await rToken.unprotectedMint(alice, dec(100000, 18))

      // Check she has more R than her position debt
      const aliceBal = await rToken.balanceOf(alice)
      const aliceDebt = await getPositionEntireDebt(alice)
      assert.isTrue(aliceBal.gt(aliceDebt))

      // Alice attempts to close her position
      await assertRevert(positionManager.closePosition({ from: alice }), "PositionManager: Only one position in the system")
    })

    it("closePosition(): reduces a Position's collateral, debt, and stake to zero", async () => {
      const alice_wstETHBalance_Before = toBN(await wstETHTokenMock.balanceOf(alice))
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      const aliceCollBefore = await getPositionEntireColl(alice)
      const aliceDebtBefore = await getPositionEntireDebt(alice)
      const dennisR = await rToken.balanceOf(dennis)
      assert.isTrue(aliceCollBefore.gt(toBN('0')))
      assert.isTrue(aliceDebtBefore.gt(toBN('0')))
      assert.isTrue((await getPositionStake(alice)).gt(toBN('0')))
      assert.isTrue((await positionManager.totalStakes()).gt(toBN('0')))
      assert.isTrue(dennisR.gt(toBN('0')))

      // To compensate borrowing fees
      await rToken.transfer(alice, dennisR.div(toBN(2)), { from: dennis })

      const alice_RBalance_Before = await rToken.balanceOf(alice)
      assert.isTrue(alice_RBalance_Before.gt(toBN('0')))

      // Alice attempts to close position
      await positionManager.managePosition(aliceCollBefore, false, await getActualDebtFromComposite(aliceDebtBefore), false, alice, alice, 0, { from: alice })

      assert.equal(await getPositionEntireColl(alice), '0')
      assert.equal(await getPositionEntireDebt(alice), '0')
      assert.equal(await getPositionStake(alice), '0')
      assert.isTrue(toBN(await getPositionStake(dennis)).eq(await positionManager.totalStakes()))
      assert.isTrue(toBN(await wstETHTokenMock.balanceOf(positionManager.address)).eq(await getPositionEntireColl(dennis)))
      assert.isTrue(toBN(await wstETHTokenMock.balanceOf(alice)).eq(alice_wstETHBalance_Before))
      th.assertIsApproximatelyEqual(await rToken.balanceOf(alice), alice_RBalance_Before.sub(aliceDebtBefore.sub(R_GAS_COMPENSATION)))
    })

    it("closePosition(): zero's the positions reward snapshots", async () => {
      // Dennis opens position and transfers tokens to alice
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: dennis } })

      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      // Price drops
      await priceFeed.setPrice(dec(100, 18))

      // Liquidate Bob
      await positionManager.liquidate(bob)
      assert.isFalse((await positionManager.sortedPositionsNodes(bob))[0])

      // Price bounces back
      await priceFeed.setPrice(dec(200, 18))

      // Alice and Carol open positions
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

      // Price drops ...again
      await priceFeed.setPrice(dec(100, 18))

      // Get Alice's pending reward snapshots
      assert.isTrue((await positionManager.rewardSnapshots(alice))[0].gt(toBN('0')))
      assert.isTrue((await positionManager.rewardSnapshots(alice))[1].gt(toBN('0')))

      // Liquidate Carol
      await positionManager.liquidate(carol)
      assert.isFalse((await positionManager.sortedPositionsNodes(carol))[0])

      // Get Alice's pending reward snapshots after Carol's liquidation. Check above 0
      assert.isTrue((await positionManager.rewardSnapshots(alice))[0].gt(toBN('0')))
      assert.isTrue((await positionManager.rewardSnapshots(alice))[1].gt(toBN('0')))

      // to compensate borrowing fees
      await rToken.transfer(alice, await rToken.balanceOf(dennis), { from: dennis })

      await priceFeed.setPrice(dec(200, 18))

      // Alice closes position
      await positionManager.managePosition(
        await getPositionEntireColl(alice),
        false,
        await getActualDebtFromComposite(await getPositionEntireDebt(alice)),
        false,
        alice,
        alice,
        0,
        { from: alice }
      )

      // Check Alice's pending reward snapshots are zero
      assert.equal((await positionManager.rewardSnapshots(alice))[0], '0')
      assert.equal((await positionManager.rewardSnapshots(alice))[1], '0')
    })

    it("closePosition(): succeeds when borrower's R balance is equals to his entire debt and borrowing rate = 0%", async () => {
      await openPosition({ extraRAmount: toBN(dec(15000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })

      // Check if borrowing rate is 0
      const borrowingRate = await positionManager.getBorrowingRate()
      assert.isTrue(borrowingRate.eq(toBN(0)))

      // Confirm Bob's R balance is less than his position debt
      const B_RBal = await rToken.balanceOf(B)
      const B_positionDebt = await getPositionEntireDebt(B)

      assert.isTrue(B_positionDebt.sub(B_RBal).eq(R_GAS_COMPENSATION))

      const closePositionB = await positionManager.managePosition(
        await getPositionEntireColl(B),
        false,
        await getActualDebtFromComposite(await getPositionEntireDebt(B)),
        false,
        alice,
        alice,
        0,
        { from: B }
      )
      assert.isTrue(closePositionB.receipt.status)
    })

    it("closePosition(): reverts if borrower has insufficient R balance to repay his entire debt when borrowing rate > 0%", async () => {
      await positionManager.setBorrowingSpread(dec(5, 15), { from: owner })

      await openPosition({ extraRAmount: toBN(dec(15000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })

      // Check if borrowing rate > 0
      const borrowingRate = await positionManager.getBorrowingRate()
      assert.isTrue(borrowingRate.gt(toBN(0)))

      // Confirm Bob's R balance is less than his position debt
      const B_RBal = await rToken.balanceOf(B)
      const B_positionDebt = await getPositionEntireDebt(B)

      assert.isTrue(B_RBal.lt(B_positionDebt))

      const closePositionPromise_B = positionManager.managePosition(
        await getPositionEntireColl(B),
        false,
        await getActualDebtFromComposite(await getPositionEntireDebt(B)),
        false,
        alice,
        alice,
        0,
        { from: B }
      )

      // Check closing position reverts
      await assertRevert(closePositionPromise_B, "ERC20: burn amount exceeds balance")
    })

    // --- openPosition() ---

    it("openPosition(): Opens a position with net debt >= minimum net debt", async () => {
      // Add 1 wei to correct for rounding error in helper function
      await openPosition({maxFeePercentage: th._100pct, extraRAmount: await getNetBorrowingAmount(MIN_NET_DEBT.add(toBN(1))), upperHint: A, lowerHint:A, amount: dec(100, 30), extraParams: { from: A }})
      assert.isTrue((await positionManager.sortedPositionsNodes(A))[0])

      await openPosition({maxFeePercentage: th._100pct, extraRAmount: await getNetBorrowingAmount(MIN_NET_DEBT.add(toBN(dec(47789898, 22)))),  upperHint: A, lowerHint: A, amount: dec(100, 30), extraParams: { from: C }})
      assert.isTrue((await positionManager.sortedPositionsNodes(C))[0])
    })

    it("openPosition(): decays a non-zero base rate", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await positionManager.setBaseRate(dec(5, 16))
      await positionManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await positionManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D opens position
      await openPosition({ extraRAmount: toBN(dec(37, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check baseRate has decreased
      const baseRate_2 = await positionManager.baseRate()
      assert.isTrue(baseRate_2.lt(baseRate_1))

      // 1 hour passes
      th.fastForwardTime(3600, web3.currentProvider)

      // E opens position
      await openPosition({ extraRAmount: toBN(dec(12, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      const baseRate_3 = await positionManager.baseRate()
      assert.isTrue(baseRate_3.lt(baseRate_2))
    })

    it("openPosition(): doesn't change base rate if it is already zero", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Check baseRate is zero
      const baseRate_1 = await positionManager.baseRate()
      assert.equal(baseRate_1, '0')

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D opens position
      await openPosition({ extraRAmount: toBN(dec(37, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check baseRate is still 0
      const baseRate_2 = await positionManager.baseRate()
      assert.equal(baseRate_2, '0')

      // 1 hour passes
      th.fastForwardTime(3600, web3.currentProvider)

      // E opens position
      await openPosition({ extraRAmount: toBN(dec(12, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      const baseRate_3 = await positionManager.baseRate()
      assert.equal(baseRate_3, '0')
    })

    it("openPosition(): lastFeeOpTime doesn't update if less time than decay interval has passed since the last fee operation", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await positionManager.setBaseRate(dec(5, 16))
      await positionManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await positionManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      const lastFeeOpTime_1 = await positionManager.lastFeeOperationTime()

      // Borrower D triggers a fee
      await openPosition({ extraRAmount: toBN(dec(1, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      const lastFeeOpTime_2 = await positionManager.lastFeeOperationTime()

      // Check that the last fee operation time did not update, as borrower D's debt issuance occured
      // since before minimum interval had passed
      assert.isTrue(lastFeeOpTime_2.eq(lastFeeOpTime_1))

      // 1 minute passes
      th.fastForwardTime(60, web3.currentProvider)

      // Check that now, at least one minute has passed since lastFeeOpTime_1
      const timeNow = await th.getLatestBlockTimestamp(web3)
      assert.isTrue(toBN(timeNow).sub(lastFeeOpTime_1).gte(3600))

      // Borrower E triggers a fee
      await openPosition({ extraRAmount: toBN(dec(1, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      const lastFeeOpTime_3 = await positionManager.lastFeeOperationTime()

      // Check that the last fee operation time DID update, as borrower's debt issuance occured
      // after minimum interval had passed
      assert.isTrue(lastFeeOpTime_3.gt(lastFeeOpTime_1))
    })

    it("openPosition(): borrower can't grief the baseRate and stop it decaying by issuing debt at higher frequency than the decay granularity", async () => {
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await positionManager.setBaseRate(dec(5, 16))
      await positionManager.setLastFeeOpTimeToNow()

      // Check baseRate is non-zero
      const baseRate_1 = await positionManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 59 minutes pass
      th.fastForwardTime(3540, web3.currentProvider)

      // Assume Borrower also owns accounts D and E
      // Borrower triggers a fee, before decay interval has passed
      await openPosition({ extraRAmount: toBN(dec(1, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // 1 minute pass
      th.fastForwardTime(3540, web3.currentProvider)

      // Borrower triggers another fee
      await openPosition({ extraRAmount: toBN(dec(1, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })

      // Check base rate has decreased even though Borrower tried to stop it decaying
      const baseRate_2 = await positionManager.baseRate()
      assert.isTrue(baseRate_2.lt(baseRate_1))
    })

    it("openPosition(): borrowing at non-zero base rate sends R fee to fee recipient", async () => {
      const feeRecipient = await positionManager.feeRecipient()

      // time fast-forwards 1 year
      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_YEAR, web3.currentProvider)

      // Check feeRecipient R balance before == 0
      const feeRecipient_RBalance_Before = await rToken.balanceOf(feeRecipient)
      assert.equal(feeRecipient_RBalance_Before, '0')

      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openPosition({ extraRAmount: toBN(dec(30000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openPosition({ extraRAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })

      // Artificially make baseRate 5%
      await positionManager.setBaseRate(dec(5, 16))
      await positionManager.setLastFeeOpTimeToNow()

      // Check baseRate is now non-zero
      const baseRate_1 = await positionManager.baseRate()
      assert.isTrue(baseRate_1.gt(toBN('0')))

      // 2 hours pass
      th.fastForwardTime(7200, web3.currentProvider)

      // D opens position
      await openPosition({ extraRAmount: toBN(dec(40000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })

      // Check feeRecipient R balance after has increased
      const feeRecipient_RBalance_After = await rToken.balanceOf(feeRecipient)
      assert.isTrue(feeRecipient_RBalance_After.gt(feeRecipient_RBalance_Before))
    })

    it("openPosition(): reverts when position ICR < MCR", async () => {
      await openPosition({ extraRAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      // Bob attempts to open a 109% ICR position
      try {
        const txBob = (await openPosition({ extraRAmount: toBN(dec(5000, 18)), ICR: toBN(dec(109, 16)), extraParams: { from: bob } })).tx
        assert.isFalse(txBob.receipt.status)
      } catch (err) {
        assert.include(err.message, "revert")
      }
    })

    it("openPosition(): creates a new Position and assigns the correct collateral and debt amount", async () => {
      const debt_Before = await getPositionEntireDebt(alice)
      const coll_Before = await getPositionEntireColl(alice)

      // check coll and debt before
      assert.equal(debt_Before, 0)
      assert.equal(coll_Before, 0)

      const RRequest = MIN_NET_DEBT
      await openPosition({amount: dec(100, 'ether'), extraParams: { from: alice }})

      // Get the expected debt based on the R request (adding fee and liq. reserve on top)
      const expectedDebt = RRequest
        .add(await positionManager.getBorrowingFee(RRequest))
        .add(R_GAS_COMPENSATION)

      const debt_After = await getPositionEntireDebt(alice)
      const coll_After = await getPositionEntireColl(alice)

      // check coll and debt after
      assert.isTrue(coll_After.gt('0'))
      assert.isTrue(debt_After.gt('0'))
      assert.isTrue(debt_After.eq(expectedDebt))
    })

    it("openPosition(): creates a stake and adds it to total stakes", async () => {
      const aliceStakeBefore = await getPositionStake(alice)
      const totalStakesBefore = await positionManager.totalStakes()

      assert.equal(aliceStakeBefore, '0')
      assert.equal(totalStakesBefore, '0')

      await openPosition({ extraRAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceCollAfter = await getPositionEntireColl(alice)
      const aliceStakeAfter = await getPositionStake(alice)
      assert.isTrue(aliceCollAfter.gt(toBN('0')))
      assert.isTrue(aliceStakeAfter.eq(aliceCollAfter))

      const totalStakesAfter = await positionManager.totalStakes()

      assert.isTrue(totalStakesAfter.eq(aliceStakeAfter))
    })

    it("openPosition(): inserts Position to Sorted Positions list", async () => {
      // Check before
      const alicePositionInList_Before = (await positionManager.sortedPositionsNodes(alice))[0]
      const listIsEmpty_Before = (await positionManager.sortedPositions())[3] == 0
      assert.equal(alicePositionInList_Before, false)
      assert.equal(listIsEmpty_Before, true)

      await openPosition({ extraRAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      // check after
      const alicePositionInList_After = (await positionManager.sortedPositionsNodes(alice))[0]
      const listIsEmpty_After = (await positionManager.sortedPositions())[3] == 0
      assert.equal(alicePositionInList_After, true)
      assert.equal(listIsEmpty_After, false)
    })

    it("openPosition(): Increases the position manager's raw ether balance by correct amount", async () => {
      const positionManager_RawEther_Before = await wstETHTokenMock.balanceOf(positionManager.address)
      assert.equal(positionManager_RawEther_Before, 0)

      await openPosition({ extraRAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      const aliceCollAfter = await getPositionEntireColl(alice)

      const positionManager_RawEther_After = toBN(await wstETHTokenMock.balanceOf(positionManager.address))
      assert.isTrue(positionManager_RawEther_After.eq(aliceCollAfter))
    })

    it("openPosition(): records up-to-date initial snapshots of L_CollateralBalance and L_RDebt", async () => {
      // --- SETUP ---

      await openPosition({ extraRAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openPosition({ extraRAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

      // --- TEST ---

      // price drops to 1ETH:100R, reducing Carol's ICR below MCR
      await priceFeed.setPrice(dec(100, 18));

      // close Carol's Position, liquidating her 1 ether and 180R.
      const liquidationTx = await positionManager.liquidate(carol, { from: owner });
      const [liquidatedDebt, liquidatedColl, gasComp] = th.getEmittedLiquidationValues(liquidationTx)

      /* with total stakes = 10 ether, after liquidation, L_CollateralBalance should equal 1/10 ether per-ether-staked,
       and L_R should equal 18 R per-ether-staked. */

      const L_CollateralBalance = await positionManager.L_CollateralBalance()
      const L_R = await positionManager.L_RDebt()

      assert.isTrue(L_CollateralBalance.gt(toBN('0')))
      assert.isTrue(L_R.gt(toBN('0')))


      await priceFeed.setPrice(DEFAULT_PRICE);
      // Bob opens position
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

      // Check Bob's snapshots of L_CollateralBalance and L_R equal the respective current values
      const bob_rewardSnapshot = await positionManager.rewardSnapshots(bob)
      const bob_ETHrewardSnapshot = bob_rewardSnapshot[0]
      const bob_RDebtRewardSnapshot = bob_rewardSnapshot[1]

      assert.isAtMost(th.getDifference(bob_ETHrewardSnapshot, L_CollateralBalance), 1000)
      assert.isAtMost(th.getDifference(bob_RDebtRewardSnapshot, L_R), 1000)
    })

    it("openPosition(): allows a user to open a Position, then close it, then re-open it", async () => {
      // Open Positions
      await openPosition({ extraRAmount: toBN(dec(10000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: whale } })
      await openPosition({ extraRAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      await openPosition({ extraRAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

      assert.isTrue((await positionManager.sortedPositionsNodes(alice))[0])

      // to compensate borrowing fees
      await rToken.transfer(alice, dec(10000, 18), { from: whale })

      await positionManager.managePosition(
        await getPositionEntireColl(alice),
        false,
        await getActualDebtFromComposite(await getPositionEntireDebt(alice)),
        false,
        alice,
        alice,
        0,
        { from: alice }
      )
      assert.isFalse((await positionManager.sortedPositionsNodes(alice))[0])

      await openPosition({ extraRAmount: toBN(dec(5000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })
      assert.isTrue((await positionManager.sortedPositionsNodes(alice))[0])
    })

    it("openPosition(): increases the Position's R debt by the correct amount", async () => {
      // check before
      const alice_Position_Before = await positionManager.positions(alice)
      const debt_Before = alice_Position_Before[0]
      assert.equal(debt_Before, 0)

      await openPosition({ extraRAmount: await getOpenPositionRAmount(dec(10000, 18)), amount: dec(100, 'ether'), extraParams: { from: alice }})

      // check after
      const alice_Position_After = await positionManager.positions(alice)
      const debt_After = alice_Position_After[0]
      assert.isTrue(debt_After.gt(dec(10000, 18)))
    })

    it("openPosition(): increases user RToken balance by correct amount", async () => {
      // check before
      const alice_RTokenBalance_Before = await rToken.balanceOf(alice)
      assert.equal(alice_RTokenBalance_Before, 0)

      await openPosition({ extraRAmount: dec(10000, 18), amount: dec(100, 'ether'), extraParams: { from: alice }})

      // check after
      const alice_RTokenBalance_After = await rToken.balanceOf(alice)
      assert.isTrue(alice_RTokenBalance_After.gt(dec(10000, 18)))
    })
  })

contract('Reset chain state', async accounts => { })
