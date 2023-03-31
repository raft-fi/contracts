const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")

const th = testHelpers.TestHelper
const dec = th.dec
const toBN = th.toBN
const assertRevert = th.assertRevert
const mv = testHelpers.MoneyValues
const timeValues = testHelpers.TimeValues

const GAS_PRICE = 10000000


/* NOTE: Some tests involving ETH redemption fees do not test for specific fee values.
 * Some only test that the fees are non-zero when they should occur.
 *
 * Specific ETH gain values will depend on the final fee schedule used, and the final choices for
 * the parameter BETA in the PositionManager, which is still TBD based on economic modelling.
 *
 */
contract('PositionManager', async accounts => {

  const _18_zeros = '000000000000000000'
  const ZERO_ADDRESS = th.ZERO_ADDRESS

  const [
    owner,
    alice, bob, carol, dennis, erin, flyn, graham, harriet, ida,
    defaulter_1, defaulter_2, defaulter_3, defaulter_4, whale,
    A, B, C, D, E] = accounts;

  let priceFeed
  let rToken
  let positionManager
  let wstETHTokenMock

  let contracts

  const getOpenPositionRAmount = async (totalDebt) => th.getOpenPositionRAmount(contracts, totalDebt)
  const getNetBorrowingAmount = async (debtWithFee) => th.getNetBorrowingAmount(contracts, debtWithFee)
  const openPosition = async (params) => th.openPosition(contracts, params)
  const withdrawR = async (params) => th.withdrawR(contracts, params)

  beforeEach(async () => {
    contracts = await deploymentHelper.deployLiquityCore(owner)

    priceFeed = contracts.priceFeedTestnet
    rToken = contracts.rToken
    positionManager = contracts.positionManager
    wstETHTokenMock = contracts.wstETHTokenMock

    await th.fillAccountsWithWstETH(contracts, [
      owner,
      alice, bob, carol, dennis, erin, flyn, graham, harriet, ida,
      defaulter_1, defaulter_2, defaulter_3, defaulter_4, whale,
      A, B, C, D, E,
    ])
  })

  it('liquidate(): closes a Position that has ICR < MCR', async () => {
    await openPosition({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })
    await openPosition({ ICR: toBN(dec(4, 18)), extraParams: { from: alice } })

    const price = await priceFeed.getPrice()
    const ICR_Before = await positionManager.getCurrentICR(alice, price)
    assert.equal(ICR_Before, dec(4, 18))

    const MCR = (await positionManager.MCR()).toString()
    assert.equal(MCR.toString(), '1100000000000000000')

    // Alice increases debt to 180 R, lowering her ICR to 1.11
    const A_RWithdrawal = await getNetBorrowingAmount(dec(130, 18))

    const targetICR = toBN('1111111111111111111')
    await withdrawR({ ICR: targetICR, extraParams: { from: alice } })

    const ICR_AfterWithdrawal = await positionManager.getCurrentICR(alice, price)
    assert.isAtMost(th.getDifference(ICR_AfterWithdrawal, targetICR), 100)

    // price drops to 1ETH:100R, reducing Alice's ICR below MCR
    await priceFeed.setPrice('100000000000000000000');

    // close Position
    await positionManager.liquidate(alice, { from: owner });

    // check the Position is successfully closed, and removed from sortedList
    const status = (await positionManager.positions(alice))[3]
    assert.equal(status, 3)  // status enum 3 corresponds to "Closed by liquidation"
    const alice_Position_isInSortedList = (await positionManager.sortedPositionsNodes(alice))[0]
    assert.isFalse(alice_Position_isInSortedList)
  })
  
  it("liquidate(): removes the Position's stake from the total stakes", async () => {
    // --- SETUP ---
    await deploymentHelper.mintR(rToken, owner);
    const { collateral: A_collateral } = await openPosition({ ICR: toBN(dec(4, 18)), extraParams: { from: alice } })
    const { collateral: B_collateral } = await openPosition({ ICR: toBN(dec(21, 17)), extraParams: { from: bob } })

    // --- TEST ---

    // check totalStakes before
    const totalStakes_Before = (await positionManager.totalStakes()).toString()
    assert.equal(totalStakes_Before, A_collateral.add(B_collateral))

    // price drops to 1ETH:100R, reducing Bob's ICR below MCR
    await priceFeed.setPrice('100000000000000000000');

    // Close Bob's Position
    await positionManager.liquidate(bob, { from: owner });

    // check totalStakes after
    const totalStakes_After = (await positionManager.totalStakes()).toString()
    assert.equal(totalStakes_After, A_collateral)
  })

  it("liquidate(): updates the snapshots of total stakes and total collateral", async () => {
    // --- SETUP ---
    await deploymentHelper.mintR(rToken, owner);
    const { collateral: A_collateral, totalDebt: A_totalDebt } = await openPosition({ ICR: toBN(dec(4, 18)), extraParams: { from: alice } })
    const { collateral: B_collateral, totalDebt: B_totalDebt } = await openPosition({ ICR: toBN(dec(2, 18)), extraParams: { from: bob } })

    // --- TEST ---

    // check snapshots before
    const totalStakesSnapshot_Before = (await positionManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_Before = (await positionManager.totalCollateralSnapshot()).toString()
    assert.equal(totalStakesSnapshot_Before, '0')
    assert.equal(totalCollateralSnapshot_Before, '0')

    // price drops to 1ETH:100R, reducing Bob's ICR below MCR
    await priceFeed.setPrice('100000000000000000000');
    // close Bob's Position
    await positionManager.liquidate(bob, { from: owner });

    /* check snapshots after. Total stakes should be equal to the  remaining stake then the system:
    10 ether, Alice's stake.

    Total collateral should be equal to Alice's collateral plus her pending ETH reward (Bob’s collaterale*0.995 ether), earned
    from the liquidation of Bob's Position */
    const totalStakesSnapshot_After = (await positionManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot_After = (await positionManager.totalCollateralSnapshot()).toString()

    assert.equal(totalStakesSnapshot_After, A_collateral)
    assert.equal(totalCollateralSnapshot_After, A_collateral.add(th.applyLiquidationFee(B_collateral)))
  })

  it("liquidate(): updates the L_CollateralBalance and L_RDebt reward-per-unit-staked totals", async () => {
    // --- SETUP ---
    const { collateral: A_collateral, totalDebt: A_totalDebt } = await openPosition({ ICR: toBN(dec(8, 18)), extraParams: { from: alice } })
    const { collateral: B_collateral, totalDebt: B_totalDebt } = await openPosition({ ICR: toBN(dec(4, 18)), extraParams: { from: bob } })
    const { collateral: C_collateral, totalDebt: C_totalDebt } = await openPosition({ ICR: toBN(dec(111, 16)), extraParams: { from: carol } })

    // --- TEST ---

    // price drops to 1ETH:100R, reducing Carols's ICR below MCR
    await priceFeed.setPrice('100000000000000000000');

    // close Carol's Position.
    assert.isTrue((await positionManager.sortedPositionsNodes(carol))[0])
    await positionManager.liquidate(carol, { from: owner });
    assert.isFalse((await positionManager.sortedPositionsNodes(carol))[0])

    const L_ETH_AfterCarolLiquidated = await positionManager.L_CollateralBalance()
    const L_RDebt_AfterCarolLiquidated = await positionManager.L_RDebt()

    const L_ETH_expected_1 = th.applyLiquidationFee(C_collateral).mul(mv._1e18BN).div(A_collateral.add(B_collateral))
    const L_RDebt_expected_1 = C_totalDebt.mul(mv._1e18BN).div(A_collateral.add(B_collateral))
    assert.isAtMost(th.getDifference(L_ETH_AfterCarolLiquidated, L_ETH_expected_1), 100)
    assert.isAtMost(th.getDifference(L_RDebt_AfterCarolLiquidated, L_RDebt_expected_1), 100)

    // Bob now withdraws R, bringing his ICR to 1.11
    const { increasedTotalDebt: B_increasedTotalDebt } = await withdrawR({ ICR: toBN(dec(111, 16)), extraParams: { from: bob } })

    // price drops to 1ETH:50R, reducing Bob's ICR below MCR
    await priceFeed.setPrice(dec(50, 18));
    const price = await priceFeed.getPrice()

    // close Bob's Position
    assert.isTrue((await positionManager.sortedPositionsNodes(bob))[0])
    await positionManager.liquidate(bob, { from: owner });
    assert.isFalse((await positionManager.sortedPositionsNodes(bob))[0])

    /* Alice now has all the active stake. totalStakes in the system is now 10 ether.

   Bob's pending collateral reward and debt reward are applied to his Position
   before his liquidation.

   The system rewards-per-unit-staked should now be:

   L_CollateralBalance = (0.995 / 20) + (10.4975*0.995  / 10) = 1.09425125 ETH
   L_RDebt = (180 / 20) + (890 / 10) = 98 R */
    const L_ETH_AfterBobLiquidated = await positionManager.L_CollateralBalance()
    const L_RDebt_AfterBobLiquidated = await positionManager.L_RDebt()

    const L_ETH_expected_2 = L_ETH_expected_1.add(th.applyLiquidationFee(B_collateral.add(B_collateral.mul(L_ETH_expected_1).div(mv._1e18BN))).mul(mv._1e18BN).div(A_collateral))
    const L_RDebt_expected_2 = L_RDebt_expected_1.add(B_totalDebt.add(B_increasedTotalDebt).add(B_collateral.mul(L_RDebt_expected_1).div(mv._1e18BN)).mul(mv._1e18BN).div(A_collateral))
    assert.isAtMost(th.getDifference(L_ETH_AfterBobLiquidated, L_ETH_expected_2), 100)
    assert.isAtMost(th.getDifference(L_RDebt_AfterBobLiquidated, L_RDebt_expected_2), 100)
  })

  it("liquidate(): Liquidates undercollateralized position if there are two positions in the system", async () => {
    await deploymentHelper.mintR(rToken, owner);
    wstETHTokenMock.approve(positionManager.address, dec(100, 'ether'), { from: bob})
    await openPosition({ ICR: toBN(dec(200, 18)), amount: dec(100, 'ether'), extraParams: { from: bob } })

    // Alice creates a single position with 0.7 ETH and a debt of 70 R
    await openPosition({ ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

    // Set ETH:USD price to 105
    await priceFeed.setPrice('105000000000000000000')
    const price = await priceFeed.getPrice()

    const alice_ICR = (await positionManager.getCurrentICR(alice, price)).toString()
    assert.equal(alice_ICR, '1050000000000000000')

    // Liquidate the position
    await positionManager.liquidate(alice, { from: owner })

    const alice_isInSortedList = (await positionManager.sortedPositionsNodes(alice))[0]
    assert.isFalse(alice_isInSortedList)

    const bob_isInSortedList = (await positionManager.sortedPositionsNodes(bob))[0]
    assert.isTrue(bob_isInSortedList)
  })

  it("liquidate(): reverts if position is non-existent", async () => {
    await openPosition({ ICR: toBN(dec(4, 18)), extraParams: { from: alice } })
    await openPosition({ ICR: toBN(dec(21, 17)), extraParams: { from: bob } })

    assert.equal((await positionManager.positions(carol))[3], 0) // check position non-existent

    assert.isFalse((await positionManager.sortedPositionsNodes(carol))[0])

    try {
      const txCarol = await positionManager.liquidate(carol)

      assert.isFalse(txCarol.receipt.status)
    } catch (err) {
      assert.include(err.message, "revert")
      assert.include(err.message, "PositionManagerPositionNotActive")
    }
  })

  it("liquidate(): reverts if position has been closed", async () => {
    await openPosition({ ICR: toBN(dec(8, 18)), extraParams: { from: alice } })
    await openPosition({ ICR: toBN(dec(4, 18)), extraParams: { from: bob } })
    await openPosition({ ICR: toBN(dec(2, 18)), extraParams: { from: carol } })

    assert.isTrue((await positionManager.sortedPositionsNodes(carol))[0])

    // price drops, Carol ICR falls below MCR
    await priceFeed.setPrice(dec(100, 18))

    // Carol liquidated, and her position is closed
    const txCarol_L1 = await positionManager.liquidate(carol)
    assert.isTrue(txCarol_L1.receipt.status)

    assert.isFalse((await positionManager.sortedPositionsNodes(carol))[0])

    assert.equal((await positionManager.positions(carol))[3], 3)  // check position closed by liquidation

    try {
      const txCarol_L2 = await positionManager.liquidate(carol)

      assert.isFalse(txCarol_L2.receipt.status)
    } catch (err) {
      assert.include(err.message, "revert")
      assert.include(err.message, "PositionManagerPositionNotActive")
    }
  })

  it("liquidate(): does nothing if position has >= 110% ICR", async () => {
    await openPosition({ ICR: toBN(dec(3, 18)), extraParams: { from: whale } })
    await openPosition({ ICR: toBN(dec(3, 18)), extraParams: { from: bob } })

    const listSize_Before = ((await positionManager.sortedPositions())[3]).toString()

    const price = await priceFeed.getPrice()

    // Check Bob's ICR > 110%
    const bob_ICR = await positionManager.getCurrentICR(bob, price)
    assert.isTrue(bob_ICR.gte(mv._MCR))

    // Attempt to liquidate bob
    await assertRevert(positionManager.liquidate(bob), "PositionManager: nothing to liquidate")

    // Check bob active, check whale active
    assert.isTrue(((await positionManager.sortedPositionsNodes(bob))[0]))
    assert.isTrue(((await positionManager.sortedPositionsNodes(whale))[0]))

    const listSize_After = ((await positionManager.sortedPositions())[3]).toString()

    assert.equal(listSize_Before, listSize_After)
  })

  it("liquidate(): does not alter the liquidated user's token balance", async () => {
    await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: whale } })
    const { rAmount: A_RAmount } = await openPosition({ ICR: toBN(dec(2, 18)), extraRAmount: toBN(dec(300, 18)), extraParams: { from: alice } })
    const { rAmount: B_RAmount } = await openPosition({ ICR: toBN(dec(2, 18)), extraRAmount: toBN(dec(200, 18)), extraParams: { from: bob } })
    const { rAmount: C_RAmount } = await openPosition({ ICR: toBN(dec(2, 18)), extraRAmount: toBN(dec(100, 18)), extraParams: { from: carol } })

    await priceFeed.setPrice(dec(100, 18))

    // Check sortedList size
    assert.equal(((await positionManager.sortedPositions())[3]).toString(), '4')

    // Liquidate A, B and C
    await positionManager.liquidate(alice)
    await positionManager.liquidate(bob)
    await positionManager.liquidate(carol)

    // Confirm A, B, C closed
    assert.isFalse((await positionManager.sortedPositionsNodes(alice))[0])
    assert.isFalse((await positionManager.sortedPositionsNodes(bob))[0])
    assert.isFalse((await positionManager.sortedPositionsNodes(carol))[0])

    // Check sortedList size reduced to 1
    assert.equal(((await positionManager.sortedPositions())[3]).toString(), '1')

    // Confirm token balances have not changed
    assert.equal((await rToken.balanceOf(alice)).toString(), A_RAmount)
    assert.equal((await rToken.balanceOf(bob)).toString(), B_RAmount)
    assert.equal((await rToken.balanceOf(carol)).toString(), C_RAmount)
  })

  it("liquidate(): liquidates based on entire/collateral debt (including pending rewards), not raw collateral/debt", async () => {
    await deploymentHelper.mintR(rToken, owner);
    await openPosition({ ICR: toBN(dec(8, 18)), extraRAmount: toBN(dec(100, 18)), extraParams: { from: alice } })
    await openPosition({ ICR: toBN(dec(221, 16)), extraRAmount: toBN(dec(100, 18)), extraParams: { from: bob } })
    await openPosition({ ICR: toBN(dec(2, 18)), extraRAmount: toBN(dec(100, 18)), extraParams: { from: carol } })

    // Defaulter opens with 60 R, 0.6 ETH
    await openPosition({ ICR: toBN(dec(2, 18)), extraParams: { from: defaulter_1 } })

    // Price drops
    await priceFeed.setPrice(dec(100, 18))
    const price = await priceFeed.getPrice()

    const alice_ICR_Before = await positionManager.getCurrentICR(alice, price)
    const bob_ICR_Before = await positionManager.getCurrentICR(bob, price)
    const carol_ICR_Before = await positionManager.getCurrentICR(carol, price)

    /* Before liquidation:
    Alice ICR: = (2 * 100 / 50) = 400%
    Bob ICR: (1 * 100 / 90.5) = 110.5%
    Carol ICR: (1 * 100 / 100 ) =  100%

    Therefore Alice and Bob above the MCR, Carol is below */
    assert.isTrue(alice_ICR_Before.gte(mv._MCR))
    assert.isTrue(bob_ICR_Before.gte(mv._MCR))
    assert.isTrue(carol_ICR_Before.lte(mv._MCR))

    /* Liquidate defaulter. 30 R and 0.3 ETH is distributed between A, B and C.

    A receives (30 * 2/4) = 15 R, and (0.3*2/4) = 0.15 ETH
    B receives (30 * 1/4) = 7.5 R, and (0.3*1/4) = 0.075 ETH
    C receives (30 * 1/4) = 7.5 R, and (0.3*1/4) = 0.075 ETH
    */
    await positionManager.liquidate(defaulter_1)

    const alice_ICR_After = await positionManager.getCurrentICR(alice, price)
    const bob_ICR_After = await positionManager.getCurrentICR(bob, price)
    const carol_ICR_After = await positionManager.getCurrentICR(carol, price)

    /* After liquidation:

    Alice ICR: (10.15 * 100 / 60) = 183.33%
    Bob ICR:(1.075 * 100 / 98) =  109.69%
    Carol ICR: (1.075 *100 /  107.5 ) = 100.0%

    Check Alice is above MCR, Bob below, Carol below. */


    assert.isTrue(alice_ICR_After.gte(mv._MCR))
    assert.isTrue(bob_ICR_After.lte(mv._MCR))
    assert.isTrue(carol_ICR_After.lte(mv._MCR))

    /* Though Bob's true ICR (including pending rewards) is below the MCR,
    check that Bob's raw coll and debt has not changed, and that his "raw" ICR is above the MCR */
    const bob_Coll = (await positionManager.positions(bob))[1]
    const bob_Debt = (await positionManager.positions(bob))[0]

    const bob_rawICR = bob_Coll.mul(toBN(dec(100, 18))).div(bob_Debt)
    assert.isTrue(bob_rawICR.gte(mv._MCR))

    await openPosition({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })
    // Liquidate Alice, Bob, Carol
    await assertRevert(positionManager.liquidate(alice), "PositionManager: nothing to liquidate")
    await positionManager.liquidate(bob)
    await positionManager.liquidate(carol)

    /* Check Alice stays active, Carol gets liquidated, and Bob gets liquidated
   (because his pending rewards bring his ICR < MCR) */
    assert.isTrue((await positionManager.sortedPositionsNodes(alice))[0])
    assert.isFalse((await positionManager.sortedPositionsNodes(bob))[0])
    assert.isFalse((await positionManager.sortedPositionsNodes(carol))[0])

    // Check position statuses - A active (1),  B and C liquidated (3)
    assert.equal((await positionManager.positions(alice))[3].toString(), '1')
    assert.equal((await positionManager.positions(bob))[3].toString(), '3')
    assert.equal((await positionManager.positions(carol))[3].toString(), '3')
  })

  // --- batchLiquidatePositions() ---

  it.skip('batchLiquidatePositions(): liquidates a Position that a) was skipped in a previous liquidation and b) has pending rewards', async () => {
    // A, B, C, D, E open positions
    await deploymentHelper.mintR(contracts.rToken);
    await openPosition({ ICR: toBN(dec(300, 16)), extraParams: { from: C } })
    await openPosition({ ICR: toBN(dec(364, 16)), extraParams: { from: D } })
    await openPosition({ ICR: toBN(dec(364, 16)), extraParams: { from: E } })
    await openPosition({ ICR: toBN(dec(120, 16)), extraParams: { from: A } })
    await openPosition({ ICR: toBN(dec(133, 16)), extraParams: { from: B } })

    // Price drops
    await priceFeed.setPrice(dec(175, 18))
    let price = await priceFeed.getPrice()

    // A gets liquidated, creates pending rewards for all
    const liqTxA = await positionManager.liquidate(A)
    assert.isTrue(liqTxA.receipt.status)
    assert.isFalse((await positionManager.sortedPositionsNodes(A))[0])

    // Price drops
    await priceFeed.setPrice(dec(100, 18))
    price = await priceFeed.getPrice()

    // Attempt to liquidate B and C, which skips C in the liquidation since it is immune
    const liqTxBC = await positionManager.liquidatePositions(2)
    assert.isTrue(liqTxBC.receipt.status)
    assert.isFalse((await positionManager.sortedPositionsNodes(B))[0])
    assert.isTrue((await positionManager.sortedPositionsNodes(C))[0])
    assert.isTrue((await positionManager.sortedPositionsNodes(D))[0])
    assert.isTrue((await positionManager.sortedPositionsNodes(E))[0])

    // // All remaining positions D and E repay a little debt, applying their pending rewards
    assert.isTrue(((await positionManager.sortedPositions())[3]).eq(toBN('3')))
    await positionManager.repayR(dec(1, 18), D, D, {from: D})
    await positionManager.repayR(dec(1, 18), E, E, {from: E})

    // Check C is the only position that has pending rewards
    assert.isTrue(await positionManager.hasPendingRewards(C))
    assert.isFalse(await positionManager.hasPendingRewards(D))
    assert.isFalse(await positionManager.hasPendingRewards(E))

    await priceFeed.setPrice(dec(50, 18))

    // Try to liquidate C again. Check it succeeds and closes C's position
    const liqTx2 = await positionManager.batchLiquidatePositions([C,D])
    assert.isTrue(liqTx2.receipt.status)
    assert.isFalse((await positionManager.sortedPositionsNodes(C))[0])
    assert.isFalse((await positionManager.sortedPositionsNodes(D))[0])
    assert.isTrue((await positionManager.sortedPositionsNodes(E))[0])
    assert.isTrue(((await positionManager.sortedPositions())[3]).eq(toBN('1')))
  })

  it('batchLiquidatePositions(): closes every position with ICR < MCR in the given array', async () => {
    // --- SETUP ---
    await openPosition({ ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

    await openPosition({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    await openPosition({ ICR: toBN(dec(133, 16)), extraParams: { from: bob } })
    await openPosition({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    await openPosition({ ICR: toBN(dec(2000, 16)), extraParams: { from: dennis } })
    await openPosition({ ICR: toBN(dec(1800, 16)), extraParams: { from: erin } })

    // Check full sorted list size is 6
    assert.equal(((await positionManager.sortedPositions())[3]).toString(), '6')

    // --- TEST ---

    // Price drops to 1ETH:100R, reducing A, B, C ICR below MCR
    await priceFeed.setPrice(dec(100, 18));
    const price = await priceFeed.getPrice()

    // Confirm positions A-C are ICR < 110%
    assert.isTrue((await positionManager.getCurrentICR(alice, price)).lt(mv._MCR))
    assert.isTrue((await positionManager.getCurrentICR(bob, price)).lt(mv._MCR))
    assert.isTrue((await positionManager.getCurrentICR(carol, price)).lt(mv._MCR))

    // Confirm D-E are ICR > 110%
    assert.isTrue((await positionManager.getCurrentICR(dennis, price)).gte(mv._MCR))
    assert.isTrue((await positionManager.getCurrentICR(erin, price)).gte(mv._MCR))

    // Confirm Whale is ICR >= 110%
    assert.isTrue((await positionManager.getCurrentICR(whale, price)).gte(mv._MCR))

    liquidationArray = [alice, bob, carol, dennis, erin]
    await positionManager.batchLiquidatePositions(liquidationArray);

    // Confirm positions A-C have been removed from the system
    assert.isFalse((await positionManager.sortedPositionsNodes(alice))[0])
    assert.isFalse((await positionManager.sortedPositionsNodes(bob))[0])
    assert.isFalse((await positionManager.sortedPositionsNodes(carol))[0])

    // Check all positions A-C are now closed by liquidation
    assert.equal((await positionManager.positions(alice))[3].toString(), '3')
    assert.equal((await positionManager.positions(bob))[3].toString(), '3')
    assert.equal((await positionManager.positions(carol))[3].toString(), '3')

    // Check sorted list has been reduced to length 3
    assert.equal(((await positionManager.sortedPositions())[3]).toString(), '3')
  })

  it('batchLiquidatePositions(): does not liquidate positions that are not in the given array', async () => {
    // --- SETUP ---
    await openPosition({ ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

    await openPosition({ ICR: toBN(dec(200, 16)), extraParams: { from: alice } })
    await openPosition({ ICR: toBN(dec(180, 16)), extraParams: { from: bob } })
    await openPosition({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: toBN(dec(500, 18)), extraParams: { from: dennis } })
    await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: toBN(dec(500, 18)), extraParams: { from: erin } })

    // Check full sorted list size is 6
    assert.equal(((await positionManager.sortedPositions())[3]).toString(), '6')

    // --- TEST ---

    // Price drops to 1ETH:100R, reducing A, B, C ICR below MCR
    await priceFeed.setPrice(dec(100, 18));
    const price = await priceFeed.getPrice()

    // Confirm positions A-E are ICR < 110%
    assert.isTrue((await positionManager.getCurrentICR(alice, price)).lt(mv._MCR))
    assert.isTrue((await positionManager.getCurrentICR(bob, price)).lt(mv._MCR))
    assert.isTrue((await positionManager.getCurrentICR(carol, price)).lt(mv._MCR))
    assert.isTrue((await positionManager.getCurrentICR(dennis, price)).lt(mv._MCR))
    assert.isTrue((await positionManager.getCurrentICR(erin, price)).lt(mv._MCR))

    liquidationArray = [alice, bob]  // C-E not included
    await positionManager.batchLiquidatePositions(liquidationArray);

    // Confirm positions A-B have been removed from the system
    assert.isFalse((await positionManager.sortedPositionsNodes(alice))[0])
    assert.isFalse((await positionManager.sortedPositionsNodes(bob))[0])

    // Check all positions A-B are now closed by liquidation
    assert.equal((await positionManager.positions(alice))[3].toString(), '3')
    assert.equal((await positionManager.positions(bob))[3].toString(), '3')

    // Confirm positions C-E remain in the system
    assert.isTrue((await positionManager.sortedPositionsNodes(carol))[0])
    assert.isTrue((await positionManager.sortedPositionsNodes(dennis))[0])
    assert.isTrue((await positionManager.sortedPositionsNodes(erin))[0])

    // Check all positions C-E are still active
    assert.equal((await positionManager.positions(carol))[3].toString(), '1')
    assert.equal((await positionManager.positions(dennis))[3].toString(), '1')
    assert.equal((await positionManager.positions(erin))[3].toString(), '1')

    // Check sorted list has been reduced to length 4
    assert.equal(((await positionManager.sortedPositions())[3]).toString(), '4')
  })

  it('batchLiquidatePositions(): does not close positions with ICR >= MCR in the given array', async () => {
    // --- SETUP ---
    await openPosition({ ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

    await openPosition({ ICR: toBN(dec(190, 16)), extraParams: { from: alice } })
    await openPosition({ ICR: toBN(dec(120, 16)), extraParams: { from: bob } })
    await openPosition({ ICR: toBN(dec(195, 16)), extraParams: { from: carol } })
    await openPosition({ ICR: toBN(dec(2000, 16)), extraParams: { from: dennis } })
    await openPosition({ ICR: toBN(dec(1800, 16)), extraParams: { from: erin } })

    // Check full sorted list size is 6
    assert.equal(((await positionManager.sortedPositions())[3]).toString(), '6')

    // --- TEST ---

    // Price drops to 1ETH:100R, reducing A, B, C ICR below MCR
    await priceFeed.setPrice(dec(100, 18));
    const price = await priceFeed.getPrice()

    // Confirm positions A-C are ICR < 110%
    assert.isTrue((await positionManager.getCurrentICR(alice, price)).lt(mv._MCR))
    assert.isTrue((await positionManager.getCurrentICR(bob, price)).lt(mv._MCR))
    assert.isTrue((await positionManager.getCurrentICR(carol, price)).lt(mv._MCR))

    // Confirm D-E are ICR >= 110%
    assert.isTrue((await positionManager.getCurrentICR(dennis, price)).gte(mv._MCR))
    assert.isTrue((await positionManager.getCurrentICR(erin, price)).gte(mv._MCR))

    // Confirm Whale is ICR > 110%
    assert.isTrue((await positionManager.getCurrentICR(whale, price)).gte(mv._MCR))

    liquidationArray = [alice, bob, carol, dennis, erin]
    await positionManager.batchLiquidatePositions(liquidationArray);

    // Confirm positions D-E and whale remain in the system
    assert.isTrue((await positionManager.sortedPositionsNodes(dennis))[0])
    assert.isTrue((await positionManager.sortedPositionsNodes(erin))[0])
    assert.isTrue((await positionManager.sortedPositionsNodes(whale))[0])

    // Check all positions D-E and whale remain active
    assert.equal((await positionManager.positions(dennis))[3].toString(), '1')
    assert.equal((await positionManager.positions(erin))[3].toString(), '1')
    assert.isTrue((await positionManager.sortedPositionsNodes(whale))[0])

    // Check sorted list has been reduced to length 3
    assert.equal(((await positionManager.sortedPositions())[3]).toString(), '3')
  })

  it('batchLiquidatePositions(): reverts if array is empty', async () => {
    // --- SETUP ---
    await openPosition({ ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

    await openPosition({ ICR: toBN(dec(190, 16)), extraParams: { from: alice } })
    await openPosition({ ICR: toBN(dec(120, 16)), extraParams: { from: bob } })
    await openPosition({ ICR: toBN(dec(195, 16)), extraParams: { from: carol } })
    await openPosition({ ICR: toBN(dec(2000, 16)), extraParams: { from: dennis } })
    await openPosition({ ICR: toBN(dec(1800, 16)), extraParams: { from: erin } })

    // Check full sorted list size is 6
    assert.equal(((await positionManager.sortedPositions())[3]).toString(), '6')

    // --- TEST ---

    // Price drops to 1ETH:100R, reducing A, B, C ICR below MCR
    await priceFeed.setPrice(dec(100, 18));

    liquidationArray = []
    try {
      const tx = await positionManager.batchLiquidatePositions(liquidationArray);
      assert.isFalse(tx.receipt.status)
    } catch (error) {
      assert.include(error.message, "PositionArrayEmpty")
    }
  })

  it("batchLiquidatePositions(): skips if position is non-existent", async () => {
    // --- SETUP ---
    await deploymentHelper.mintR(contracts.rToken);
    await openPosition({ ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

    const { totalDebt: A_debt } = await openPosition({ ICR: toBN(dec(201, 16)), extraParams: { from: alice } })
    const { totalDebt: B_debt } = await openPosition({ ICR: toBN(dec(212, 16)), extraParams: { from: bob } })
    await openPosition({ ICR: toBN(dec(2000, 16)), extraParams: { from: dennis } })
    await openPosition({ ICR: toBN(dec(1800, 16)), extraParams: { from: erin } })

    assert.equal((await positionManager.positions(carol))[3], 0) // check position non-existent

    // Check full sorted list size is 6
    assert.equal(((await positionManager.sortedPositions())[3]).toString(), '5')

    // --- TEST ---

    // Price drops to 1ETH:100R, reducing A, B, C ICR below MCR
    await priceFeed.setPrice(dec(100, 18));
    const price = await priceFeed.getPrice()

    // Confirm positions A-B are ICR < 110%
    assert.isTrue((await positionManager.getCurrentICR(alice, price)).lt(mv._MCR))
    assert.isTrue((await positionManager.getCurrentICR(bob, price)).lt(mv._MCR))

    // Confirm D-E are ICR > 110%
    assert.isTrue((await positionManager.getCurrentICR(dennis, price)).gte(mv._MCR))
    assert.isTrue((await positionManager.getCurrentICR(erin, price)).gte(mv._MCR))

    // Confirm Whale is ICR >= 110%
    assert.isTrue((await positionManager.getCurrentICR(whale, price)).gte(mv._MCR))

    const preLiquidationBalance = await rToken.balanceOf(owner);
    // Liquidate - position C in between the ones to be liquidated!
    const liquidationArray = [alice, carol, bob, dennis, erin]
    await positionManager.batchLiquidatePositions(liquidationArray);

    // Confirm positions A-B have been removed from the system
    assert.isFalse((await positionManager.sortedPositionsNodes(alice))[0])
    assert.isFalse((await positionManager.sortedPositionsNodes(bob))[0])

    // Check all positions A-B are now closed by liquidation
    assert.equal((await positionManager.positions(alice))[3].toString(), '3')
    assert.equal((await positionManager.positions(bob))[3].toString(), '3')

    // Check sorted list has been reduced to length 3
    assert.equal(((await positionManager.sortedPositions())[3]).toString(), '3')

    // Confirm position C non-existent
    assert.isFalse((await positionManager.sortedPositionsNodes(carol))[0])
    assert.equal((await positionManager.positions(carol))[3].toString(), '0')

    const rGasCompensation = await positionManager.R_GAS_COMPENSATION();
    th.assertIsApproximatelyEqual((await rToken.balanceOf(owner)).toString(), preLiquidationBalance.sub(A_debt).sub(B_debt).add(rGasCompensation).add(rGasCompensation))
  })

  it("batchLiquidatePositions(): skips if a position has been closed", async () => {
    // --- SETUP ---
    await deploymentHelper.mintR(contracts.rToken, whale);
    await openPosition({ ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

    const { totalDebt: A_debt } = await openPosition({ ICR: toBN(dec(202, 16)), extraParams: { from: alice } })
    const { totalDebt: B_debt } = await openPosition({ ICR: toBN(dec(210, 16)), extraParams: { from: bob } })
    await openPosition({ ICR: toBN(dec(195, 16)), extraParams: { from: carol } })
    await openPosition({ ICR: toBN(dec(2000, 16)), extraParams: { from: dennis } })
    await openPosition({ ICR: toBN(dec(1800, 16)), extraParams: { from: erin } })

    assert.isTrue((await positionManager.sortedPositionsNodes(carol))[0])

    // Check full sorted list size is 6
    assert.equal(((await positionManager.sortedPositions())[3]).toString(), '6')

    // Whale transfers to Carol so she can close her position
    await rToken.transfer(carol, dec(100, 18), { from: whale })

    // --- TEST ---

    // Price drops to 1ETH:100R, reducing A, B, C ICR below MCR
    await priceFeed.setPrice(dec(100, 18));
    const price = await priceFeed.getPrice()

    // Carol liquidated, and her position is closed
    const txCarolClose = await positionManager.closePosition({ from: carol })
    assert.isTrue(txCarolClose.receipt.status)

    assert.isFalse((await positionManager.sortedPositionsNodes(carol))[0])

    assert.equal((await positionManager.positions(carol))[3], 2)  // check position closed

    // Confirm positions A-B are ICR < 110%
    assert.isTrue((await positionManager.getCurrentICR(alice, price)).lt(mv._MCR))
    assert.isTrue((await positionManager.getCurrentICR(bob, price)).lt(mv._MCR))

    // Confirm D-E are ICR > 110%
    assert.isTrue((await positionManager.getCurrentICR(dennis, price)).gte(mv._MCR))
    assert.isTrue((await positionManager.getCurrentICR(erin, price)).gte(mv._MCR))

    // Confirm Whale is ICR >= 110%
    assert.isTrue((await positionManager.getCurrentICR(whale, price)).gte(mv._MCR))

    const preLiquidationBalance = await rToken.balanceOf(whale);
    // Liquidate - position C in between the ones to be liquidated!
    const liquidationArray = [alice, carol, bob, dennis, erin]
    await positionManager.batchLiquidatePositions(liquidationArray, { from: whale });

    // Confirm positions A-B have been removed from the system
    assert.isFalse((await positionManager.sortedPositionsNodes(alice))[0])
    assert.isFalse((await positionManager.sortedPositionsNodes(bob))[0])

    // Check all positions A-B are now closed by liquidation
    assert.equal((await positionManager.positions(alice))[3].toString(), '3')
    assert.equal((await positionManager.positions(bob))[3].toString(), '3')
    // Position C still closed by user
    assert.equal((await positionManager.positions(carol))[3].toString(), '2')

    // Check sorted list has been reduced to length 3
    assert.equal(((await positionManager.sortedPositions())[3]).toString(), '3')

    // Check liquidator has only been reduced by A-B
    const rGasCompensation = await positionManager.R_GAS_COMPENSATION();
    th.assertIsApproximatelyEqual((await rToken.balanceOf(whale)).toString(), preLiquidationBalance.sub(A_debt).sub(B_debt).add(rGasCompensation).add(rGasCompensation))
  })

  // --- redemptions ---

  it('redeemCollateral(): cancels the provided R with debt from Positions with the lowest ICRs and sends an equivalent amount of Ether', async () => {
    // --- SETUP ---
    const { totalDebt: A_totalDebt } = await openPosition({ ICR: toBN(dec(310, 16)), extraRAmount: dec(10, 18), extraParams: { from: alice } })
    const { netDebt: B_netDebt } = await openPosition({ ICR: toBN(dec(290, 16)), extraRAmount: dec(8, 18), extraParams: { from: bob } })
    const { netDebt: C_netDebt } = await openPosition({ ICR: toBN(dec(250, 16)), extraRAmount: dec(10, 18), extraParams: { from: carol } })
    const partialRedemptionAmount = toBN(2)
    const redemptionAmount = C_netDebt.add(B_netDebt).add(partialRedemptionAmount)
    // start Dennis with a high ICR
    await openPosition({ ICR: toBN(dec(100, 18)), extraRAmount: redemptionAmount, extraParams: { from: dennis } })

    const dennis_ETHBalance_Before = toBN(await wstETHTokenMock.balanceOf(dennis))

    const dennis_RBalance_Before = await rToken.balanceOf(dennis)

    const price = await priceFeed.getPrice()
    assert.equal(price, dec(200, 18))

    // --- TEST ---

    // Hints for redeeming 20 R
    const firstRedemptionHint = carol;
    const partialRedemptionHintNICR = toBN("1550000000000000000")
    const lowerPartialRedemptionHint = alice
    const upperPartialRedemptionHint = dennis

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    // Dennis redeems 20 R
    // Don't pay for gas, as it makes it easier to calculate the received Ether
    const redemptionTx = await positionManager.redeemCollateral(
      redemptionAmount,
      firstRedemptionHint,
      upperPartialRedemptionHint,
      lowerPartialRedemptionHint,
      partialRedemptionHintNICR,
      0, th._100pct,
      {
        from: dennis,
        gasPrice: GAS_PRICE
      }
    )

    const ETHFee = th.getEmittedRedemptionValues(redemptionTx)[3]

    const alice_Position_After = await positionManager.positions(alice)
    const bob_Position_After = await positionManager.positions(bob)
    const carol_Position_After = await positionManager.positions(carol)

    const alice_debt_After = alice_Position_After[0].toString()
    const bob_debt_After = bob_Position_After[0].toString()
    const carol_debt_After = carol_Position_After[0].toString()

    /* check that Dennis' redeemed 20 R has been cancelled with debt from Bobs's Position (8) and Carol's Position (10).
    The remaining lot (2) is sent to Alice's Position, who had the best ICR.
    It leaves her with (3) R debt + 50 for gas compensation. */
    th.assertIsApproximatelyEqual(alice_debt_After, A_totalDebt.sub(partialRedemptionAmount))
    assert.equal(bob_debt_After, '0')
    assert.equal(carol_debt_After, '0')

    const dennis_ETHBalance_After = toBN(await wstETHTokenMock.balanceOf(dennis))
    const receivedETH = dennis_ETHBalance_After.sub(dennis_ETHBalance_Before)

    const expectedTotalETHDrawn = redemptionAmount.div(toBN(200)) // convert redemptionAmount R to ETH, at ETH:USD price 200
    const expectedReceivedETH = expectedTotalETHDrawn.sub(toBN(ETHFee))

    th.assertIsApproximatelyEqual(expectedReceivedETH, receivedETH)

    const dennis_RBalance_After = (await rToken.balanceOf(dennis)).toString()
    assert.equal(dennis_RBalance_After, dennis_RBalance_Before.sub(redemptionAmount))
  })

  it('redeemCollateral(): with invalid first hint, zero address', async () => {
    // --- SETUP ---
    const { totalDebt: A_totalDebt } = await openPosition({ ICR: toBN(dec(310, 16)), extraRAmount: dec(10, 18), extraParams: { from: alice } })
    const { netDebt: B_netDebt } = await openPosition({ ICR: toBN(dec(290, 16)), extraRAmount: dec(8, 18), extraParams: { from: bob } })
    const { netDebt: C_netDebt } = await openPosition({ ICR: toBN(dec(250, 16)), extraRAmount: dec(10, 18), extraParams: { from: carol } })
    const partialRedemptionAmount = toBN(2)
    const redemptionAmount = C_netDebt.add(B_netDebt).add(partialRedemptionAmount)
    // start Dennis with a high ICR
    await openPosition({ ICR: toBN(dec(100, 18)), extraRAmount: redemptionAmount, extraParams: { from: dennis } })

    const dennis_ETHBalance_Before = toBN(await wstETHTokenMock.balanceOf(dennis))

    const dennis_RBalance_Before = await rToken.balanceOf(dennis)

    const price = await priceFeed.getPrice()
    assert.equal(price, dec(200, 18))

    // --- TEST ---

    // Hints for redeeming 20 R
    const partialRedemptionHintNICR = toBN("1550000000000000000")
    const upperPartialRedemptionHint = alice;
    const lowerPartialRedemptionHint = dennis;

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    // Dennis redeems 20 R
    // Don't pay for gas, as it makes it easier to calculate the received Ether
    const redemptionTx = await positionManager.redeemCollateral(
      redemptionAmount,
      ZERO_ADDRESS, // invalid first hint
      upperPartialRedemptionHint,
      lowerPartialRedemptionHint,
      partialRedemptionHintNICR,
      0, th._100pct,
      {
        from: dennis,
        gasPrice: GAS_PRICE
      }
    )

    const ETHFee = th.getEmittedRedemptionValues(redemptionTx)[3]

    const alice_Position_After = await positionManager.positions(alice)
    const bob_Position_After = await positionManager.positions(bob)
    const carol_Position_After = await positionManager.positions(carol)

    const alice_debt_After = alice_Position_After[0].toString()
    const bob_debt_After = bob_Position_After[0].toString()
    const carol_debt_After = carol_Position_After[0].toString()

    /* check that Dennis' redeemed 20 R has been cancelled with debt from Bobs's Position (8) and Carol's Position (10).
    The remaining lot (2) is sent to Alice's Position, who had the best ICR.
    It leaves her with (3) R debt + 50 for gas compensation. */
    th.assertIsApproximatelyEqual(alice_debt_After, A_totalDebt.sub(partialRedemptionAmount))
    assert.equal(bob_debt_After, '0')
    assert.equal(carol_debt_After, '0')

    const dennis_ETHBalance_After = toBN(await wstETHTokenMock.balanceOf(dennis))
    const receivedETH = dennis_ETHBalance_After.sub(dennis_ETHBalance_Before)

    const expectedTotalETHDrawn = redemptionAmount.div(toBN(200)) // convert redemptionAmount R to ETH, at ETH:USD price 200
    const expectedReceivedETH = expectedTotalETHDrawn.sub(toBN(ETHFee))

    th.assertIsApproximatelyEqual(expectedReceivedETH, receivedETH)

    const dennis_RBalance_After = (await rToken.balanceOf(dennis)).toString()
    assert.equal(dennis_RBalance_After, dennis_RBalance_Before.sub(redemptionAmount))
  })

  it('redeemCollateral(): with invalid first hint, non-existent position', async () => {
    // --- SETUP ---
    const { totalDebt: A_totalDebt } = await openPosition({ ICR: toBN(dec(310, 16)), extraRAmount: dec(10, 18), extraParams: { from: alice } })
    const { netDebt: B_netDebt } = await openPosition({ ICR: toBN(dec(290, 16)), extraRAmount: dec(8, 18), extraParams: { from: bob } })
    const { netDebt: C_netDebt } = await openPosition({ ICR: toBN(dec(250, 16)), extraRAmount: dec(10, 18), extraParams: { from: carol } })
    const partialRedemptionAmount = toBN(2)
    const redemptionAmount = C_netDebt.add(B_netDebt).add(partialRedemptionAmount)
    // start Dennis with a high ICR
    await openPosition({ ICR: toBN(dec(100, 18)), extraRAmount: redemptionAmount, extraParams: { from: dennis } })

    const dennis_ETHBalance_Before = toBN(await wstETHTokenMock.balanceOf(dennis))

    const dennis_RBalance_Before = await rToken.balanceOf(dennis)

    const price = await priceFeed.getPrice()
    assert.equal(price, dec(200, 18))

    // --- TEST ---

    // Hints for redeeming 20 R
    const partialRedemptionHintNICR = toBN("1550000000000000000")
    const upperPartialRedemptionHint = alice;
    const lowerPartialRedemptionHint = dennis;

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    // Dennis redeems 20 R
    // Don't pay for gas, as it makes it easier to calculate the received Ether
    const redemptionTx = await positionManager.redeemCollateral(
      redemptionAmount,
      erin, // invalid first hint, it doesn’t have a position
      upperPartialRedemptionHint,
      lowerPartialRedemptionHint,
      partialRedemptionHintNICR,
      0, th._100pct,
      {
        from: dennis,
        gasPrice: GAS_PRICE
      }
    )

    const ETHFee = th.getEmittedRedemptionValues(redemptionTx)[3]

    const alice_Position_After = await positionManager.positions(alice)
    const bob_Position_After = await positionManager.positions(bob)
    const carol_Position_After = await positionManager.positions(carol)

    const alice_debt_After = alice_Position_After[0].toString()
    const bob_debt_After = bob_Position_After[0].toString()
    const carol_debt_After = carol_Position_After[0].toString()

    /* check that Dennis' redeemed 20 R has been cancelled with debt from Bobs's Position (8) and Carol's Position (10).
    The remaining lot (2) is sent to Alice's Position, who had the best ICR.
    It leaves her with (3) R debt + 50 for gas compensation. */
    th.assertIsApproximatelyEqual(alice_debt_After, A_totalDebt.sub(partialRedemptionAmount))
    assert.equal(bob_debt_After, '0')
    assert.equal(carol_debt_After, '0')

    const dennis_ETHBalance_After = toBN(await wstETHTokenMock.balanceOf(dennis))
    const receivedETH = dennis_ETHBalance_After.sub(dennis_ETHBalance_Before)

    const expectedTotalETHDrawn = redemptionAmount.div(toBN(200)) // convert redemptionAmount R to ETH, at ETH:USD price 200
    const expectedReceivedETH = expectedTotalETHDrawn.sub(toBN(ETHFee))

    th.assertIsApproximatelyEqual(expectedReceivedETH, receivedETH)

    const dennis_RBalance_After = (await rToken.balanceOf(dennis)).toString()
    assert.equal(dennis_RBalance_After, dennis_RBalance_Before.sub(redemptionAmount))
  })

  it('redeemCollateral(): with invalid first hint, position below MCR', async () => {
    // --- SETUP ---
    const { totalDebt: A_totalDebt } = await openPosition({ ICR: toBN(dec(310, 16)), extraRAmount: dec(10, 18), extraParams: { from: alice } })
    const { netDebt: B_netDebt } = await openPosition({ ICR: toBN(dec(290, 16)), extraRAmount: dec(8, 18), extraParams: { from: bob } })
    const { netDebt: C_netDebt } = await openPosition({ ICR: toBN(dec(250, 16)), extraRAmount: dec(10, 18), extraParams: { from: carol } })
    const partialRedemptionAmount = toBN(2)
    const redemptionAmount = C_netDebt.add(B_netDebt).add(partialRedemptionAmount)
    // start Dennis with a high ICR
    await openPosition({ ICR: toBN(dec(100, 18)), extraRAmount: redemptionAmount, extraParams: { from: dennis } })

    const dennis_ETHBalance_Before = toBN(await wstETHTokenMock.balanceOf(dennis))

    const dennis_RBalance_Before = await rToken.balanceOf(dennis)

    const price = await priceFeed.getPrice()
    assert.equal(price, dec(200, 18))

    // Increase price to start erin, and decrease it again so its ICR is under MCR
    await priceFeed.setPrice(price.mul(toBN(2)))
    await openPosition({ ICR: toBN(dec(2, 18)), extraParams: { from: erin } })
    await priceFeed.setPrice(price)


    // --- TEST ---

    // Hints for redeeming 20 R
    const partialRedemptionHintNICR = toBN("1550000000000000000")
    const upperPartialRedemptionHint = alice;
    const lowerPartialRedemptionHint = dennis;

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    // Dennis redeems 20 R
    // Don't pay for gas, as it makes it easier to calculate the received Ether
    const redemptionTx = await positionManager.redeemCollateral(
      redemptionAmount,
      erin, // invalid position, below MCR
      upperPartialRedemptionHint,
      lowerPartialRedemptionHint,
      partialRedemptionHintNICR,
      0, th._100pct,
      {
        from: dennis,
        gasPrice: GAS_PRICE
      }
    )

    const ETHFee = th.getEmittedRedemptionValues(redemptionTx)[3]

    const alice_Position_After = await positionManager.positions(alice)
    const bob_Position_After = await positionManager.positions(bob)
    const carol_Position_After = await positionManager.positions(carol)

    const alice_debt_After = alice_Position_After[0].toString()
    const bob_debt_After = bob_Position_After[0].toString()
    const carol_debt_After = carol_Position_After[0].toString()

    /* check that Dennis' redeemed 20 R has been cancelled with debt from Bobs's Position (8) and Carol's Position (10).
    The remaining lot (2) is sent to Alice's Position, who had the best ICR.
    It leaves her with (3) R debt + 50 for gas compensation. */
    th.assertIsApproximatelyEqual(alice_debt_After, A_totalDebt.sub(partialRedemptionAmount))
    assert.equal(bob_debt_After, '0')
    assert.equal(carol_debt_After, '0')

    const dennis_ETHBalance_After = toBN(await wstETHTokenMock.balanceOf(dennis))
    const receivedETH = dennis_ETHBalance_After.sub(dennis_ETHBalance_Before)

    const expectedTotalETHDrawn = redemptionAmount.div(toBN(200)) // convert redemptionAmount R to ETH, at ETH:USD price 200
    const expectedReceivedETH = expectedTotalETHDrawn.sub(toBN(ETHFee))

    th.assertIsApproximatelyEqual(expectedReceivedETH, receivedETH)

    const dennis_RBalance_After = (await rToken.balanceOf(dennis)).toString()
    assert.equal(dennis_RBalance_After, dennis_RBalance_Before.sub(redemptionAmount))
  })

  it('redeemCollateral(): ends the redemption sequence when the token redemption request has been filled', async () => {
    // --- SETUP ---
    await openPosition({ ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

    // Alice, Bob, Carol, Dennis, erin open positions
    const { netDebt: A_debt } = await openPosition({ ICR: toBN(dec(290, 16)), extraRAmount: dec(20, 18), extraParams: { from: alice } })
    const { netDebt: B_debt } = await openPosition({ ICR: toBN(dec(290, 16)), extraRAmount: dec(20, 18), extraParams: { from: bob } })
    const { netDebt: C_debt } = await openPosition({ ICR: toBN(dec(290, 16)), extraRAmount: dec(20, 18), extraParams: { from: carol } })
    const redemptionAmount = A_debt.add(B_debt).add(C_debt)
    const { totalDebt: D_totalDebt, collateral: D_coll } = await openPosition({ ICR: toBN(dec(300, 16)), extraRAmount: dec(10, 18), extraParams: { from: dennis } })
    const { totalDebt: E_totalDebt, collateral: E_coll } = await openPosition({ ICR: toBN(dec(300, 16)), extraRAmount: dec(10, 18), extraParams: { from: erin } })

    // --- TEST ---

    // open position from redeemer.  Redeemer has highest ICR (100ETH, 100 R), 20000%
    const { rAmount: F_RAmount } = await openPosition({ ICR: toBN(dec(200, 18)), extraRAmount: redemptionAmount.mul(toBN(2)), extraParams: { from: flyn } })

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    // Flyn redeems collateral
    await positionManager.redeemCollateral(redemptionAmount, alice, alice, alice, 0, 0, th._100pct, { from: flyn })

    // Check Flyn's redemption has reduced his balance from 100 to (100-60) = 40 R
    const flynBalance = await rToken.balanceOf(flyn)
    th.assertIsApproximatelyEqual(flynBalance, F_RAmount.sub(redemptionAmount))

    // Check debt of Alice, Bob, Carol
    const alice_Debt = (await positionManager.positions(alice))[0]
    const bob_Debt = (await positionManager.positions(bob))[0]
    const carol_Debt = (await positionManager.positions(carol))[0]

    assert.equal(alice_Debt, 0)
    assert.equal(bob_Debt, 0)
    assert.equal(carol_Debt, 0)

    // check Alice, Bob and Carol positions are closed by redemption
    const alice_Status = (await positionManager.positions(alice))[3]
    const bob_Status = (await positionManager.positions(bob))[3]
    const carol_Status = (await positionManager.positions(carol))[3]
    assert.equal(alice_Status, 4)
    assert.equal(bob_Status, 4)
    assert.equal(carol_Status, 4)

    // check debt and coll of Dennis, erin has not been impacted by redemption
    const dennis_Debt = (await positionManager.positions(dennis))[0]
    const erin_Debt = (await positionManager.positions(erin))[0]

    th.assertIsApproximatelyEqual(dennis_Debt, D_totalDebt)
    th.assertIsApproximatelyEqual(erin_Debt, E_totalDebt)

    const dennis_Coll = (await positionManager.positions(dennis))[1]
    const erin_Coll = (await positionManager.positions(erin))[1]

    assert.equal(dennis_Coll.toString(), D_coll.toString())
    assert.equal(erin_Coll.toString(), E_coll.toString())
  })

  it('redeemCollateral(): ends the redemption sequence when max iterations have been reached', async () => {
    // --- SETUP ---
    await openPosition({ ICR: toBN(dec(100, 18)), extraParams: { from: whale } })

    // Alice, Bob, Carol open positions with equal collateral ratio
    const { netDebt: A_debt } = await openPosition({ ICR: toBN(dec(286, 16)), extraRAmount: dec(20, 18), extraParams: { from: alice } })
    const { netDebt: B_debt } = await openPosition({ ICR: toBN(dec(286, 16)), extraRAmount: dec(20, 18), extraParams: { from: bob } })
    const { netDebt: C_debt, totalDebt: C_totalDebt } = await openPosition({ ICR: toBN(dec(286, 16)), extraRAmount: dec(20, 18), extraParams: { from: carol } })
    const redemptionAmount = A_debt.add(B_debt)
    const attemptedRedemptionAmount = redemptionAmount.add(C_debt)

    // --- TEST ---

    // open position from redeemer.  Redeemer has highest ICR (100ETH, 100 R), 20000%
    const { rAmount: F_RAmount } = await openPosition({ ICR: toBN(dec(200, 18)), extraRAmount: redemptionAmount.mul(toBN(2)), extraParams: { from: flyn } })

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    // Flyn redeems collateral with only two iterations
    await positionManager.redeemCollateral(attemptedRedemptionAmount, alice, alice, alice, 0, 2, th._100pct, { from: flyn })

    // Check Flyn's redemption has reduced his balance from 100 to (100-40) = 60 R
    const flynBalance = (await rToken.balanceOf(flyn)).toString()
    th.assertIsApproximatelyEqual(flynBalance, F_RAmount.sub(redemptionAmount))

    // Check debt of Alice, Bob, Carol
    const alice_Debt = (await positionManager.positions(alice))[0]
    const bob_Debt = (await positionManager.positions(bob))[0]
    const carol_Debt = (await positionManager.positions(carol))[0]

    assert.equal(alice_Debt, 0)
    assert.equal(bob_Debt, 0)
    th.assertIsApproximatelyEqual(carol_Debt, C_totalDebt)

    // check Alice and Bob positions are closed, but Carol is not
    const alice_Status = (await positionManager.positions(alice))[3]
    const bob_Status = (await positionManager.positions(bob))[3]
    const carol_Status = (await positionManager.positions(carol))[3]
    assert.equal(alice_Status, 4)
    assert.equal(bob_Status, 4)
    assert.equal(carol_Status, 1)
  })
  it('redeemCollateral(): doesnt perform the final partial redemption in the sequence if the hint is out-of-date', async () => {
    // --- SETUP ---
    const { totalDebt: A_totalDebt } = await openPosition({ ICR: toBN(dec(363, 16)), extraRAmount: dec(5, 18), extraParams: { from: alice } })
    const { netDebt: B_netDebt } = await openPosition({ ICR: toBN(dec(344, 16)), extraRAmount: dec(8, 18), extraParams: { from: bob } })
    const { netDebt: C_netDebt } = await openPosition({ ICR: toBN(dec(333, 16)), extraRAmount: dec(10, 18), extraParams: { from: carol } })

    const partialRedemptionAmount = toBN(2)
    const fullfilledRedemptionAmount = C_netDebt.add(B_netDebt)
    const redemptionAmount = fullfilledRedemptionAmount.add(partialRedemptionAmount)

    await openPosition({ ICR: toBN(dec(100, 18)), extraRAmount: redemptionAmount, extraParams: { from: dennis } })

    const dennis_ETHBalance_Before = toBN(await wstETHTokenMock.balanceOf(dennis))

    const dennis_RBalance_Before = await rToken.balanceOf(dennis)

    const price = await priceFeed.getPrice()
    assert.equal(price, dec(200, 18))

    // --- TEST ---

    // Hints for redeeming 20 R
    const firstRedemptionHint = carol;
    const partialRedemptionHintNICR = toBN("1550000000000000000")
    const lowerPartialRedemptionHint = alice
    const upperPartialRedemptionHint = dennis

    const frontRunRedepmtion = toBN(dec(1, 18))
    // Oops, another transaction gets in the way
    {
      // Hints for redeeming 20 R
      const firstRedemptionHint = carol;
      const partialRedemptionHintNICR = toBN("1665579890492782478")
      const lowerPartialRedemptionHint = carol
      const upperPartialRedemptionHint = bob

      // skip bootstrapping phase
      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

      // Alice redeems 1 R from Carol's Position
      await positionManager.redeemCollateral(
        frontRunRedepmtion,
        firstRedemptionHint,
        upperPartialRedemptionHint,
        lowerPartialRedemptionHint,
        partialRedemptionHintNICR,
        0, th._100pct,
        { from: alice }
      )
    }

    // Dennis tries to redeem 20 R
    const redemptionTx = await positionManager.redeemCollateral(
      redemptionAmount,
      firstRedemptionHint,
      upperPartialRedemptionHint,
      lowerPartialRedemptionHint,
      partialRedemptionHintNICR,
      0, th._100pct,
      {
        from: dennis,
        gasPrice: GAS_PRICE
      }
    )

    const ETHFee = th.getEmittedRedemptionValues(redemptionTx)[3]

    // Since Alice already redeemed 1 R from Carol's Position, Dennis was  able to redeem:
    //  - 9 R from Carol's
    //  - 8 R from Bob's
    // for a total of 17 R.

    // Dennis calculated his hint for redeeming 2 R from Alice's Position, but after Alice's transaction
    // got in the way, he would have needed to redeem 3 R to fully complete his redemption of 20 R.
    // This would have required a different hint, therefore he ended up with a partial redemption.

    const dennis_ETHBalance_After = toBN(await wstETHTokenMock.balanceOf(dennis))
    const receivedETH = dennis_ETHBalance_After.sub(dennis_ETHBalance_Before)

    // Expect only 17 worth of ETH drawn
    const expectedTotalETHDrawn = fullfilledRedemptionAmount.sub(frontRunRedepmtion).div(toBN(200)) // redempted R converted to ETH, at ETH:USD price 200
    const expectedReceivedETH = expectedTotalETHDrawn.sub(ETHFee)

    th.assertIsApproximatelyEqual(expectedReceivedETH, receivedETH)

    const dennis_RBalance_After = (await rToken.balanceOf(dennis)).toString()
    th.assertIsApproximatelyEqual(dennis_RBalance_After, dennis_RBalance_Before.sub(fullfilledRedemptionAmount.sub(frontRunRedepmtion)))
  })

  // active debt cannot be zero, as there’s a positive min debt enforced, and at least a position must exist
  it.skip("redeemCollateral(): can redeem if there is zero active debt but non-zero debt in position manager", async () => {
    // --- SETUP ---

    const amount = await getOpenPositionRAmount(dec(110, 18))
    await openPosition({ ICR: toBN(dec(20, 18)), extraParams: { from: alice } })
    await openPosition({ ICR: toBN(dec(133, 16)), extraRAmount: amount, extraParams: { from: bob } })

    await rToken.transfer(carol, amount, { from: bob })

    const price = dec(100, 18)
    await priceFeed.setPrice(price)

    // Liquidate Bob's Position
    await positionManager.liquidatePositions(1)

    // --- TEST ---

    const carol_ETHBalance_Before = toBN(await wstETHTokenMock.balanceOf(carol))

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    const redemptionTx = await positionManager.redeemCollateral(
      amount,
      alice,
      '0x0000000000000000000000000000000000000000',
      '0x0000000000000000000000000000000000000000',
      '10367038690476190477',
      0,
      th._100pct,
      {
        from: carol,
        gasPrice: GAS_PRICE
      }
    )

    const ETHFee = th.getEmittedRedemptionValues(redemptionTx)[3]

    const carol_ETHBalance_After = toBN(await wstETHTokenMock.balanceOf(carol))

    const expectedTotalETHDrawn = toBN(amount).div(toBN(100)) // convert 100 R to ETH at ETH:USD price of 100
    const expectedReceivedETH = expectedTotalETHDrawn.sub(ETHFee)

    const receivedETH = carol_ETHBalance_After.sub(carol_ETHBalance_Before)
    assert.isTrue(expectedReceivedETH.eq(receivedETH))

    const carol_RBalance_After = (await rToken.balanceOf(carol)).toString()
    assert.equal(carol_RBalance_After, '0')
  })

  it("redeemCollateral(): doesn't touch Positions with ICR < 110%", async () => {
    // --- SETUP ---

    const { netDebt: A_debt } = await openPosition({ ICR: toBN(dec(13, 18)), extraParams: { from: alice } })
    const { rAmount: B_RAmount, totalDebt: B_totalDebt } = await openPosition({ ICR: toBN(dec(133, 16)), extraRAmount: A_debt, extraParams: { from: bob } })

    await rToken.transfer(carol, B_RAmount, { from: bob })

    // Put Bob's Position below 110% ICR
    const price = dec(100, 18)
    await priceFeed.setPrice(price)

    // --- TEST ---

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    await positionManager.redeemCollateral(
      A_debt,
      alice,
      '0x0000000000000000000000000000000000000000',
      '0x0000000000000000000000000000000000000000',
      0,
      0,
      th._100pct,
      { from: carol }
    );

    // Alice's Position was cleared of debt
    const { debt: alice_Debt_After } = await positionManager.positions(alice)
    assert.equal(alice_Debt_After, '0')

    // Bob's Position was left untouched
    const { debt: bob_Debt_After } = await positionManager.positions(bob)
    th.assertIsApproximatelyEqual(bob_Debt_After, B_totalDebt)
  });

  it.skip("redeemCollateral(): finds the last Position with ICR == 110% even if there is more than one", async () => {
    // --- SETUP ---
    const amount1 = toBN(dec(100, 18))
    const { totalDebt: A_totalDebt } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: amount1, extraParams: { from: alice } })
    const { totalDebt: B_totalDebt } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: amount1, extraParams: { from: bob } })
    const { totalDebt: C_totalDebt } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: amount1, extraParams: { from: carol } })
    const redemptionAmount = C_totalDebt.add(B_totalDebt).add(A_totalDebt)
    const { totalDebt: D_totalDebt } = await openPosition({ ICR: toBN(dec(195, 16)), extraRAmount: redemptionAmount, extraParams: { from: dennis } })

    // This will put Dennis slightly below 110%, and everyone else exactly at 110%
    const price = '110' + _18_zeros
    await priceFeed.setPrice(price)

    const orderOfPositions = [];
    let current = await sortedPositions.getFirst();

    while (current !== '0x0000000000000000000000000000000000000000') {
      orderOfPositions.push(current);
      current = await sortedPositions.getNext(current);
    }

    assert.deepEqual(orderOfPositions, [carol, bob, alice, dennis]);

    await openPosition({ ICR: toBN(dec(100, 18)), extraRAmount: dec(10, 18), extraParams: { from: whale } })

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    const tx = await positionManager.redeemCollateral(
      redemptionAmount,
      carol, // try to trick redeemCollateral by passing a hint that doesn't exactly point to the
      // last Position with ICR == 110% (which would be Alice's)
      '0x0000000000000000000000000000000000000000',
      '0x0000000000000000000000000000000000000000',
      0,
      0,
      th._100pct,
      { from: dennis }
    )

    const { debt: alice_Debt_After } = await positionManager.positions(alice)
    assert.equal(alice_Debt_After, '0')

    const { debt: bob_Debt_After } = await positionManager.positions(bob)
    assert.equal(bob_Debt_After, '0')

    const { debt: carol_Debt_After } = await positionManager.positions(carol)
    assert.equal(carol_Debt_After, '0')

    const { debt: dennis_Debt_After } = await positionManager.positions(dennis)
    th.assertIsApproximatelyEqual(dennis_Debt_After, D_totalDebt)
  });

  it("redeemCollateral(): reverts when argument _amount is 0", async () => {
    await openPosition({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })

    // Alice opens position and transfers 500R to erin, the would-be redeemer
    await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(500, 18), extraParams: { from: alice } })
    await rToken.transfer(erin, dec(500, 18), { from: alice })

    // B, C and D open positions
    await openPosition({ ICR: toBN(dec(200, 16)), extraParams: { from: bob } })
    await openPosition({ ICR: toBN(dec(200, 16)), extraParams: { from: carol } })
    await openPosition({ ICR: toBN(dec(200, 16)), extraParams: { from: dennis } })

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    // erin attempts to redeem with _amount = 0
    const redemptionTxPromise = positionManager.redeemCollateral(0, erin, erin, erin, 0, 0, th._100pct, { from: erin })
    await assertRevert(redemptionTxPromise, "PositionManager: Amount must be greater than zero")
  })

  it.skip("redeemCollateral(): caller can redeem their entire RToken balance", async () => {
    const { collateral: W_coll, totalDebt: W_totalDebt } = await openPosition({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })

    // Alice opens position and transfers 400 R to erin, the would-be redeemer
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openPosition({ ICR: toBN(dec(300, 16)), extraRAmount: dec(400, 18), extraParams: { from: alice } })
    await rToken.transfer(erin, dec(400, 18), { from: alice })

    // Check erin's balance before
    const erin_balance_before = await rToken.balanceOf(erin)
    assert.equal(erin_balance_before, dec(400, 18))

    // B, C, D open position
    await openPosition({ ICR: toBN(dec(300, 16)), extraRAmount: dec(590, 18), extraParams: { from: bob } })
    await openPosition({ ICR: toBN(dec(300, 16)), extraRAmount: dec(1990, 18), extraParams: { from: carol } })
    await openPosition({ ICR: toBN(dec(500, 16)), extraRAmount: dec(1990, 18), extraParams: { from: dennis } })

    const price = await priceFeed.getPrice()

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    // erin attempts to redeem 400 R
    const {
      firstRedemptionHint,
      partialRedemptionHintNICR
    } = await hintHelpers.getRedemptionHints(dec(400, 18), price, 0)

    const { 0: upperPartialRedemptionHint, 1: lowerPartialRedemptionHint } = await sortedPositions.findInsertPosition(
      partialRedemptionHintNICR,
      erin,
      erin
    )

    await positionManager.redeemCollateral(
      dec(400, 18),
      firstRedemptionHint,
      upperPartialRedemptionHint,
      lowerPartialRedemptionHint,
      partialRedemptionHintNICR,
      0, th._100pct,
      { from: erin })

    // Check erin's balance after
    const erin_balance_after = (await rToken.balanceOf(erin)).toString()
    assert.equal(erin_balance_after, '0')
  })

  it.skip("redeemCollateral(): reverts when requested redemption amount exceeds caller's R token balance", async () => {
    await openPosition({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })

    // Alice opens position and transfers 400 R to erin, the would-be redeemer
    await openPosition({ ICR: toBN(dec(300, 16)), extraRAmount: dec(400, 18), extraParams: { from: alice } })
    await rToken.transfer(erin, dec(400, 18), { from: alice })

    // Check erin's balance before
    const erin_balance_before = await rToken.balanceOf(erin)
    assert.equal(erin_balance_before, dec(400, 18))

    // B, C, D open position
    await openPosition({ ICR: toBN(dec(300, 16)), extraRAmount: dec(590, 18), extraParams: { from: bob } })
    await openPosition({ ICR: toBN(dec(300, 16)), extraRAmount: dec(1990, 18), extraParams: { from: carol } })
    await openPosition({ ICR: toBN(dec(500, 16)), extraRAmount: dec(1990, 18), extraParams: { from: dennis } })

    const price = await priceFeed.getPrice()

    let firstRedemptionHint
    let partialRedemptionHintNICR

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    // erin tries to redeem 1000 R
    try {
      ({
        firstRedemptionHint,
        partialRedemptionHintNICR
      } = await hintHelpers.getRedemptionHints(dec(1000, 18), price, 0))

      const { 0: upperPartialRedemptionHint_1, 1: lowerPartialRedemptionHint_1 } = await sortedPositions.findInsertPosition(
        partialRedemptionHintNICR,
        erin,
        erin
      )

      const redemptionTx = await positionManager.redeemCollateral(
        dec(1000, 18),
        firstRedemptionHint,
        upperPartialRedemptionHint_1,
        lowerPartialRedemptionHint_1,
        partialRedemptionHintNICR,
        0, th._100pct,
        { from: erin })

      assert.isFalse(redemptionTx.receipt.status)
    } catch (error) {
      assert.include(error.message, "revert")
      assert.include(error.message, "PositionManagerRedemptionAmountExceedsBalance")
    }

    // erin tries to redeem 401 R
    try {
      ({
        firstRedemptionHint,
        partialRedemptionHintNICR
      } = await hintHelpers.getRedemptionHints('401000000000000000000', price, 0))

      const { 0: upperPartialRedemptionHint_2, 1: lowerPartialRedemptionHint_2 } = await sortedPositions.findInsertPosition(
        partialRedemptionHintNICR,
        erin,
        erin
      )

      const redemptionTx = await positionManager.redeemCollateral(
        '401000000000000000000', firstRedemptionHint,
        upperPartialRedemptionHint_2,
        lowerPartialRedemptionHint_2,
        partialRedemptionHintNICR,
        0, th._100pct,
        { from: erin })
      assert.isFalse(redemptionTx.receipt.status)
    } catch (error) {
      assert.include(error.message, "revert")
      assert.include(error.message, "PositionManagerRedemptionAmountExceedsBalance")
    }

    // erin tries to redeem 239482309 R
    try {
      ({
        firstRedemptionHint,
        partialRedemptionHintNICR
      } = await hintHelpers.getRedemptionHints('239482309000000000000000000', price, 0))

      const { 0: upperPartialRedemptionHint_3, 1: lowerPartialRedemptionHint_3 } = await sortedPositions.findInsertPosition(
        partialRedemptionHintNICR,
        erin,
        erin
      )

      const redemptionTx = await positionManager.redeemCollateral(
        '239482309000000000000000000', firstRedemptionHint,
        upperPartialRedemptionHint_3,
        lowerPartialRedemptionHint_3,
        partialRedemptionHintNICR,
        0, th._100pct,
        { from: erin })
      assert.isFalse(redemptionTx.receipt.status)
    } catch (error) {
      assert.include(error.message, "revert")
      assert.include(error.message, "PositionManagerRedemptionAmountExceedsBalance")
    }

    // erin tries to redeem 2^256 - 1 R
    const maxBytes32 = toBN('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')

    try {
      ({
        firstRedemptionHint,
        partialRedemptionHintNICR
      } = await hintHelpers.getRedemptionHints('239482309000000000000000000', price, 0))

      const { 0: upperPartialRedemptionHint_4, 1: lowerPartialRedemptionHint_4 } = await sortedPositions.findInsertPosition(
        partialRedemptionHintNICR,
        erin,
        erin
      )

      const redemptionTx = await positionManager.redeemCollateral(
        maxBytes32, firstRedemptionHint,
        upperPartialRedemptionHint_4,
        lowerPartialRedemptionHint_4,
        partialRedemptionHintNICR,
        0, th._100pct,
        { from: erin })
      assert.isFalse(redemptionTx.receipt.status)
    } catch (error) {
      assert.include(error.message, "revert")
      assert.include(error.message, "PositionManagerRedemptionAmountExceedsBalance")
    }
  })

  it.skip("redeemCollateral(): value of issued ETH == face value of redeemed R (assuming 1 R has value of $1)", async () => {
    const { collateral: W_coll } = await openPosition({ ICR: toBN(dec(20, 18)), extraParams: { from: whale } })

    // Alice opens position and transfers 1000 R each to erin, Flyn, Graham
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openPosition({ ICR: toBN(dec(400, 16)), extraRAmount: dec(4990, 18), extraParams: { from: alice } })
    await rToken.transfer(erin, dec(1000, 18), { from: alice })
    await rToken.transfer(flyn, dec(1000, 18), { from: alice })
    await rToken.transfer(graham, dec(1000, 18), { from: alice })

    // B, C, D open position
    const { collateral: B_coll } = await openPosition({ ICR: toBN(dec(300, 16)), extraRAmount: dec(1590, 18), extraParams: { from: bob } })
    const { collateral: C_coll } = await openPosition({ ICR: toBN(dec(600, 16)), extraRAmount: dec(1090, 18), extraParams: { from: carol } })
    const { collateral: D_coll } = await openPosition({ ICR: toBN(dec(800, 16)), extraRAmount: dec(1090, 18), extraParams: { from: dennis } })

    const totalColl = W_coll.add(A_coll).add(B_coll).add(C_coll).add(D_coll)

    const price = await priceFeed.getPrice()

    const _120_R = '120000000000000000000'
    const _373_R = '373000000000000000000'
    const _950_R = '950000000000000000000'

    // Check Ether in position manager
    const activeETH_0 = await wstETHTokenMock.balanceOf(positionManager.address)
    assert.equal(activeETH_0, totalColl.toString());

    let firstRedemptionHint
    let partialRedemptionHintNICR


    // erin redeems 120 R
    ({
      firstRedemptionHint,
      partialRedemptionHintNICR
    } = await hintHelpers.getRedemptionHints(_120_R, price, 0))

    const { 0: upperPartialRedemptionHint_1, 1: lowerPartialRedemptionHint_1 } = await sortedPositions.findInsertPosition(
      partialRedemptionHintNICR,
      erin,
      erin
    )

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    const redemption_1 = await positionManager.redeemCollateral(
      _120_R,
      firstRedemptionHint,
      upperPartialRedemptionHint_1,
      lowerPartialRedemptionHint_1,
      partialRedemptionHintNICR,
      0, th._100pct,
      { from: erin })

    assert.isTrue(redemption_1.receipt.status);

    /* 120 R redeemed.  Expect $120 worth of ETH removed. At ETH:USD price of $200,
    ETH removed = (120/200) = 0.6 ETH
    Total active ETH = 280 - 0.6 = 279.4 ETH */

    const activeETH_1 = await wstETHTokenMock.balanceOf(positionManager.address)
    assert.equal(activeETH_1.toString(), activeETH_0.sub(toBN(_120_R).mul(mv._1e18BN).div(price)));

    // Flyn redeems 373 R
    ({
      firstRedemptionHint,
      partialRedemptionHintNICR
    } = await hintHelpers.getRedemptionHints(_373_R, price, 0))

    const { 0: upperPartialRedemptionHint_2, 1: lowerPartialRedemptionHint_2 } = await sortedPositions.findInsertPosition(
      partialRedemptionHintNICR,
      flyn,
      flyn
    )

    const redemption_2 = await positionManager.redeemCollateral(
      _373_R,
      firstRedemptionHint,
      upperPartialRedemptionHint_2,
      lowerPartialRedemptionHint_2,
      partialRedemptionHintNICR,
      0, th._100pct,
      { from: flyn })

    assert.isTrue(redemption_2.receipt.status);

    /* 373 R redeemed.  Expect $373 worth of ETH removed. At ETH:USD price of $200,
    ETH removed = (373/200) = 1.865 ETH
    Total active ETH = 279.4 - 1.865 = 277.535 ETH */
    const activeETH_2 = await wstETHTokenMock.balanceOf(positionManager.address)
    assert.equal(activeETH_2.toString(), activeETH_1.sub(toBN(_373_R).mul(mv._1e18BN).div(price)));

    // Graham redeems 950 R
    ({
      firstRedemptionHint,
      partialRedemptionHintNICR
    } = await hintHelpers.getRedemptionHints(_950_R, price, 0))

    const { 0: upperPartialRedemptionHint_3, 1: lowerPartialRedemptionHint_3 } = await sortedPositions.findInsertPosition(
      partialRedemptionHintNICR,
      graham,
      graham
    )

    const redemption_3 = await positionManager.redeemCollateral(
      _950_R,
      firstRedemptionHint,
      upperPartialRedemptionHint_3,
      lowerPartialRedemptionHint_3,
      partialRedemptionHintNICR,
      0, th._100pct,
      { from: graham })

    assert.isTrue(redemption_3.receipt.status);

    /* 950 R redeemed.  Expect $950 worth of ETH removed. At ETH:USD price of $200,
    ETH removed = (950/200) = 4.75 ETH
    Total active ETH = 277.535 - 4.75 = 272.785 ETH */
    const activeETH_3 = await wstETHTokenMock.balanceOf(positionManager.address)
    assert.equal(activeETH_3.toString(), activeETH_2.sub(toBN(_950_R).mul(mv._1e18BN).div(price)));
  })

  // it doesn’t make much sense as there’s now min debt enforced and at least one position must remain active
  // the only way to test it is before any position is opened
  it.skip("redeemCollateral(): reverts if there is zero outstanding system debt", async () => {
    // --- SETUP --- illegally mint R to Bob
    await rToken.unprotectedMint(bob, dec(100, 18))

    assert.equal((await rToken.balanceOf(bob)), dec(100, 18))

    const price = await priceFeed.getPrice()

    const {
      firstRedemptionHint,
      partialRedemptionHintNICR
    } = await hintHelpers.getRedemptionHints(dec(100, 18), price, 0)

    const { 0: upperPartialRedemptionHint, 1: lowerPartialRedemptionHint } = await sortedPositions.findInsertPosition(
      partialRedemptionHintNICR,
      bob,
      bob
    )

    // Bob tries to redeem his illegally obtained R
    try {
      const redemptionTx = await positionManager.redeemCollateral(
        dec(100, 18),
        firstRedemptionHint,
        upperPartialRedemptionHint,
        lowerPartialRedemptionHint,
        partialRedemptionHintNICR,
        0, th._100pct,
        { from: bob })
    } catch (error) {
      assert.include(error.message, "VM Exception while processing transaction")
    }

    // assert.isFalse(redemptionTx.receipt.status);
  })

  it.skip("redeemCollateral(): reverts if caller's tries to redeem more than the outstanding system debt", async () => {
    // --- SETUP --- illegally mint R to Bob
    await rToken.unprotectedMint(bob, '101000000000000000000')

    assert.equal((await rToken.balanceOf(bob)), '101000000000000000000')

    const { totalDebt: C_totalDebt } = await openPosition({ ICR: toBN(dec(1000, 16)), extraRAmount: dec(40, 18), extraParams: { from: carol } })
    const { totalDebt: D_totalDebt } = await openPosition({ ICR: toBN(dec(1000, 16)), extraRAmount: dec(40, 18), extraParams: { from: dennis } })

    const totalDebt = C_totalDebt.add(D_totalDebt)

    const price = await priceFeed.getPrice()
    const {
      firstRedemptionHint,
      partialRedemptionHintNICR
    } = await hintHelpers.getRedemptionHints('101000000000000000000', price, 0)

    const { 0: upperPartialRedemptionHint, 1: lowerPartialRedemptionHint } = await sortedPositions.findInsertPosition(
      partialRedemptionHintNICR,
      bob,
      bob
    )

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    // Bob attempts to redeem his ill-gotten 101 R, from a system that has 100 R outstanding debt
    try {
      const redemptionTx = await positionManager.redeemCollateral(
        totalDebt.add(toBN(dec(100, 18))),
        firstRedemptionHint,
        upperPartialRedemptionHint,
        lowerPartialRedemptionHint,
        partialRedemptionHintNICR,
        0, th._100pct,
        { from: bob })
    } catch (error) {
      assert.include(error.message, "VM Exception while processing transaction")
    }
  })

  it.skip('redeemCollateral(): reverts if fee eats up all returned collateral', async () => {
    // --- SETUP ---
    const { rAmount } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(1, 24), extraParams: { from: alice } })
    await openPosition({ ICR: toBN(dec(150, 16)), extraParams: { from: bob } })

    const price = await priceFeed.getPrice()
    assert.equal(price, dec(200, 18))

    // --- TEST ---

    // skip bootstrapping phase
    await th.fastForwardTime(timeValues.SECONDS_IN_ONE_WEEK * 2, web3.currentProvider)

    // keep redeeming until we get the base rate to the ceiling of 100%
    for (let i = 0; i < 2; i++) {
      // Find hints for redeeming
      const {
        firstRedemptionHint,
        partialRedemptionHintNICR
      } = await hintHelpers.getRedemptionHints(rAmount, price, 0)

      // Don't pay for gas, as it makes it easier to calculate the received Ether
      const redemptionTx = await positionManager.redeemCollateral(
        rAmount,
        firstRedemptionHint,
        ZERO_ADDRESS,
        alice,
        partialRedemptionHintNICR,
        0, th._100pct,
        {
          from: alice,
          gasPrice: GAS_PRICE
        }
      )

      await openPosition({ ICR: toBN(dec(150, 16)), extraParams: { from: bob } })
      wstETHTokenMock.approve(positionManager.address, rAmount.mul(mv._1e18BN).div(price), { from: alice})
      await positionManager.adjustPosition(th._100pct, 0, rAmount, true, alice, alice, rAmount.mul(mv._1e18BN).div(price), { from: alice })
    }

    const {
      firstRedemptionHint,
      partialRedemptionHintNICR
    } = await hintHelpers.getRedemptionHints(rAmount, price, 0)

    await assertRevert(
      positionManager.redeemCollateral(
        rAmount,
        firstRedemptionHint,
        ZERO_ADDRESS,
        alice,
        partialRedemptionHintNICR,
        0, th._100pct,
        {
          from: alice,
          gasPrice: GAS_PRICE
        }
      ),
      'PositionManager: Fee would eat up all returned collateral'
    )
  })

  it("getPendingRDebtReward(): Returns 0 if there is no pending rDebt reward", async () => {
    await deploymentHelper.mintR(contracts.rToken, whale);
    // Make some positions
    const { totalDebt } = await openPosition({ ICR: toBN(dec(201, 16)), extraRAmount: dec(100, 18), extraParams: { from: defaulter_1 } })

    await openPosition({ ICR: toBN(dec(3, 18)), extraRAmount: dec(20, 18), extraParams: { from: carol } })

    await openPosition({ ICR: toBN(dec(20, 18)), extraRAmount: totalDebt, extraParams: { from: whale } })

    // Price drops
    await priceFeed.setPrice(dec(100, 18))

    await positionManager.liquidate(defaulter_1, { from: whale })

    // Confirm defaulter_1 liquidated
    assert.isFalse((await positionManager.sortedPositionsNodes(defaulter_1))[0])

    // Confirm there are no pending rewards from liquidation
    const current_L_RDebt = await positionManager.L_RDebt()
    assert.equal(current_L_RDebt, 0)

    const carolSnapshot_L_RDebt = (await positionManager.rewardSnapshots(carol))[1]
    assert.equal(carolSnapshot_L_RDebt, 0)

    const carol_PendingRDebtReward = await positionManager.getPendingRDebtReward(carol)
    assert.equal(carol_PendingRDebtReward, 0)
  })

  it("getPendingCollateralTokenReward(): Returns 0 if there is no pending ETH reward", async () => {
    await deploymentHelper.mintR(contracts.rToken, whale);
    // make some positions
    const { totalDebt } = await openPosition({ ICR: toBN(dec(2, 18)), extraRAmount: dec(100, 18), extraParams: { from: defaulter_1 } })

    await openPosition({ ICR: toBN(dec(3, 18)), extraRAmount: dec(20, 18), extraParams: { from: carol } })

    await openPosition({ ICR: toBN(dec(20, 18)), extraRAmount: totalDebt, extraParams: { from: whale } })

    // Price drops
    await priceFeed.setPrice(dec(101, 18))

    await positionManager.liquidate(defaulter_1, { from: whale })

    // Confirm defaulter_1 liquidated
    assert.isFalse((await positionManager.sortedPositionsNodes(defaulter_1))[0])

    // Confirm there are no pending rewards from liquidation
    const current_L_ETH = await positionManager.L_CollateralBalance()
    assert.equal(current_L_ETH, 0)

    const carolSnapshot_L_ETH = (await positionManager.rewardSnapshots(carol))[0]
    assert.equal(carolSnapshot_L_ETH, 0)

    const carol_PendingETHReward = await positionManager.getPendingCollateralTokenReward(carol)
    assert.equal(carol_PendingETHReward, 0)
  })

  // --- computeICR ---

  it("computeICR(): Returns 0 if position's coll is worth 0", async () => {
    const price = 0
    const coll = dec(1, 'ether')
    const debt = dec(100, 18)

    const ICR = (await positionManager.computeICR(coll, debt, price)).toString()

    assert.equal(ICR, 0)
  })

  it("computeICR(): Returns 2^256-1 for ETH:USD = 100, coll = 1 ETH, debt = 100 R", async () => {
    const price = dec(100, 18)
    const coll = dec(1, 'ether')
    const debt = dec(100, 18)

    const ICR = (await positionManager.computeICR(coll, debt, price)).toString()

    assert.equal(ICR, dec(1, 18))
  })

  it("computeICR(): returns correct ICR for ETH:USD = 100, coll = 200 ETH, debt = 30 R", async () => {
    const price = dec(100, 18)
    const coll = dec(200, 'ether')
    const debt = dec(30, 18)

    const ICR = (await positionManager.computeICR(coll, debt, price)).toString()

    assert.isAtMost(th.getDifference(ICR, '666666666666666666666'), 1000)
  })

  it("computeICR(): returns correct ICR for ETH:USD = 250, coll = 1350 ETH, debt = 127 R", async () => {
    const price = '250000000000000000000'
    const coll = '1350000000000000000000'
    const debt = '127000000000000000000'

    const ICR = (await positionManager.computeICR(coll, debt, price))

    assert.isAtMost(th.getDifference(ICR, '2657480314960630000000'), 1000000)
  })

  it("computeICR(): returns correct ICR for ETH:USD = 100, coll = 1 ETH, debt = 54321 R", async () => {
    const price = dec(100, 18)
    const coll = dec(1, 'ether')
    const debt = '54321000000000000000000'

    const ICR = (await positionManager.computeICR(coll, debt, price)).toString()

    assert.isAtMost(th.getDifference(ICR, '1840908672520756'), 1000)
  })


  it("computeICR(): Returns 2^256-1 if position has non-zero coll and zero debt", async () => {
    const price = dec(100, 18)
    const coll = dec(1, 'ether')
    const debt = 0

    const ICR = web3.utils.toHex(await positionManager.computeICR(coll, debt, price))
    const maxBytes32 = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'

    assert.equal(ICR, maxBytes32)
  })

  // --- Getters ---

  it("getPositionStake(): Returns stake", async () => {
    const { collateral: A_coll } = await openPosition({ ICR: toBN(dec(150, 16)), extraParams: { from: A } })
    const { collateral: B_coll } = await openPosition({ ICR: toBN(dec(150, 16)), extraParams: { from: B } })

    const A_Stake = (await positionManager.positions(A))[2]
    const B_Stake = (await positionManager.positions(B))[2]

    assert.equal(A_Stake, A_coll.toString())
    assert.equal(B_Stake, B_coll.toString())
  })

  it("getPositionColl(): Returns coll", async () => {
    const { collateral: A_coll } = await openPosition({ ICR: toBN(dec(150, 16)), extraParams: { from: A } })
    const { collateral: B_coll } = await openPosition({ ICR: toBN(dec(150, 16)), extraParams: { from: B } })

    assert.equal((await positionManager.positions(A))[1], A_coll.toString())
    assert.equal((await positionManager.positions(B))[1], B_coll.toString())
  })

  it("getPositionDebt(): Returns debt", async () => {
    const { totalDebt: totalDebtA } = await openPosition({ ICR: toBN(dec(150, 16)), extraParams: { from: A } })
    const { totalDebt: totalDebtB } = await openPosition({ ICR: toBN(dec(150, 16)), extraParams: { from: B } })

    const A_Debt = (await positionManager.positions(A))[0]
    const B_Debt = (await positionManager.positions(B))[0]

    // Expect debt = requested + 0.5% fee + 50 (due to gas comp)

    assert.equal(A_Debt, totalDebtA.toString())
    assert.equal(B_Debt, totalDebtB.toString())
  })

  it("getPositionStatus(): Returns status", async () => {
    const { totalDebt: B_totalDebt } = await openPosition({ ICR: toBN(dec(150, 16)), extraParams: { from: B } })
    await openPosition({ ICR: toBN(dec(150, 16)), extraRAmount: B_totalDebt, extraParams: { from: A } })

    // to be able to repay:
    await rToken.transfer(B, B_totalDebt, { from: A })
    await positionManager.closePosition({from: B})

    const A_Status = (await positionManager.positions(A))[3]
    const B_Status = (await positionManager.positions(B))[3]
    const C_Status = (await positionManager.positions(C))[3]

    assert.equal(A_Status, '1')  // active
    assert.equal(B_Status, '2')  // closed by user
    assert.equal(C_Status, '0')  // non-existent
  })

  it("hasPendingRewards(): Returns false it position is not active", async () => {
    assert.isFalse(await positionManager.hasPendingRewards(alice))
  })
})

contract('Reset chain state', async accounts => { })
