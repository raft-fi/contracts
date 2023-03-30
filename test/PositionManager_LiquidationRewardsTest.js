const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")

const th = testHelpers.TestHelper
const dec = th.dec
const toBN = th.toBN
const getDifference = th.getDifference
const mv = testHelpers.MoneyValues

const PositionManagerTester = artifacts.require("PositionManagerTester")
const RToken = artifacts.require("RToken")

contract('PositionManager - Redistribution reward calculations', async accounts => {

  const [
    owner,
    alice, bob, carol, dennis, erin, freddy,
    A, B, C, D, E ] = accounts;

  let priceFeed
  let rToken
  let sortedPositions
  let positionManager
  let nameRegistry

  let contracts

  const getNetBorrowingAmount = async (debtWithFee) => th.getNetBorrowingAmount(contracts, debtWithFee)
  const openPosition = async (params) => th.openPosition(contracts, params)

  beforeEach(async () => {
    contracts = await deploymentHelper.deployLiquityCore(owner)

    priceFeed = contracts.priceFeedTestnet
    rToken = contracts.rToken
    sortedPositions = contracts.sortedPositions
    positionManager = contracts.positionManager
    nameRegistry = contracts.nameRegistry
    wstETHTokenMock = contracts.wstETHTokenMock

    await th.fillAccountsWithWstETH(contracts, [
      owner,
      alice, bob, carol, dennis, erin, freddy,
      A, B, C, D, E,
    ])
  })

  it("redistribution: A, B Open. B Liquidated. C, D Open. D Liquidated. Distributes correct rewards", async () => {
    // A, B open position
    const { collateral: A_coll } = await openPosition({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll } = await openPosition({ ICR: toBN(dec(190, 16)), extraParams: { from: bob } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 18))

    // L1: B liquidated
    const txB = await positionManager.liquidate(bob)
    assert.isTrue(txB.receipt.status)
    assert.isFalse(await sortedPositions.contains(bob))

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(200, 18))

    // C, D open positions
    const { collateral: C_coll } = await openPosition({ ICR: toBN(dec(400, 16)), extraParams: { from: carol } })
    const { collateral: D_coll } = await openPosition({ ICR: toBN(dec(190, 16)), extraParams: { from: dennis } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 18))

    // L2: D Liquidated
    const txD = await positionManager.liquidate(dennis)
    assert.isTrue(txB.receipt.status)
    assert.isFalse(await sortedPositions.contains(dennis))

    // Get entire coll of A and C
    const alice_Coll = ((await positionManager.positions(alice))[1]
      .add(await positionManager.getPendingCollateralTokenReward(alice)))
      .toString()
    const carol_Coll = ((await positionManager.positions(carol))[1]
      .add(await positionManager.getPendingCollateralTokenReward(carol)))
      .toString()

    /* Expected collateral:
    A: Alice receives 0.995 ETH from L1, and ~3/5*0.995 ETH from L2.
    expect aliceColl = 2 + 0.995 + 2.995/4.995 * 0.995 = 3.5916 ETH

    C: Carol receives ~2/5 ETH from L2
    expect carolColl = 2 + 2/4.995 * 0.995 = 2.398 ETH

    Total coll = 4 + 2 * 0.995 ETH
    */
    const A_collAfterL1 = A_coll.add(th.applyLiquidationFee(B_coll))
    assert.isAtMost(th.getDifference(alice_Coll, A_collAfterL1.add(A_collAfterL1.mul(th.applyLiquidationFee(D_coll)).div(A_collAfterL1.add(C_coll)))), 1000)
    assert.isAtMost(th.getDifference(carol_Coll, C_coll.add(C_coll.mul(th.applyLiquidationFee(D_coll)).div(A_collAfterL1.add(C_coll)))), 1000)

    const entireSystemColl = await wstETHTokenMock.balanceOf(positionManager.address)
    assert.equal(entireSystemColl.toString(), A_coll.add(C_coll).add(th.applyLiquidationFee(B_coll.add(D_coll))).toString())

    // check R gas compensation
    assert.equal((await rToken.balanceOf(owner)).toString(), dec(400, 18))
  })

  it("redistribution: A, B, C Open. C Liquidated. D, E, F Open. F Liquidated. Distributes correct rewards", async () => {
    // A, B C open positions
    const { collateral: A_coll } = await openPosition({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll } = await openPosition({ ICR: toBN(dec(400, 16)), extraParams: { from: bob } })
    const { collateral: C_coll } = await openPosition({ ICR: toBN(dec(190, 16)), extraParams: { from: carol } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 18))

    // L1: C liquidated
    const txC = await positionManager.liquidate(carol)
    assert.isTrue(txC.receipt.status)
    assert.isFalse(await sortedPositions.contains(carol))

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(200, 18))

    // D, E, F open positions
    const { collateral: D_coll } = await openPosition({ ICR: toBN(dec(400, 16)), extraParams: { from: dennis } })
    const { collateral: E_coll } = await openPosition({ ICR: toBN(dec(400, 16)), extraParams: { from: erin } })
    const { collateral: F_coll } = await openPosition({ ICR: toBN(dec(190, 16)), extraParams: { from: freddy } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 18))

    // L2: F Liquidated
    const txF = await positionManager.liquidate(freddy)
    assert.isTrue(txF.receipt.status)
    assert.isFalse(await sortedPositions.contains(freddy))

    // Get entire coll of A, B, D and E
    const alice_Coll = ((await positionManager.positions(alice))[1]
      .add(await positionManager.getPendingCollateralTokenReward(alice)))
      .toString()
    const bob_Coll = ((await positionManager.positions(bob))[1]
      .add(await positionManager.getPendingCollateralTokenReward(bob)))
      .toString()
    const dennis_Coll = ((await positionManager.positions(dennis))[1]
      .add(await positionManager.getPendingCollateralTokenReward(dennis)))
      .toString()
    const erin_Coll = ((await positionManager.positions(erin))[1]
      .add(await positionManager.getPendingCollateralTokenReward(erin)))
      .toString()

    /* Expected collateral:
    A and B receives 1/2 ETH * 0.995 from L1.
    total Coll: 3

    A, B, receive (2.4975)/8.995 * 0.995 ETH from L2.

    D, E receive 2/8.995 * 0.995 ETH from L2.

    expect A, B coll  = 2 +  0.4975 + 0.2763  =  ETH
    expect D, E coll  = 2 + 0.2212  =  ETH

    Total coll = 8 (non-liquidated) + 2 * 0.995 (liquidated and redistributed)
    */
    const A_collAfterL1 = A_coll.add(A_coll.mul(th.applyLiquidationFee(C_coll)).div(A_coll.add(B_coll)))
    const B_collAfterL1 = B_coll.add(B_coll.mul(th.applyLiquidationFee(C_coll)).div(A_coll.add(B_coll)))
    const totalBeforeL2 = A_collAfterL1.add(B_collAfterL1).add(D_coll).add(E_coll)
    const expected_A = A_collAfterL1.add(A_collAfterL1.mul(th.applyLiquidationFee(F_coll)).div(totalBeforeL2))
    const expected_B = B_collAfterL1.add(B_collAfterL1.mul(th.applyLiquidationFee(F_coll)).div(totalBeforeL2))
    const expected_D = D_coll.add(D_coll.mul(th.applyLiquidationFee(F_coll)).div(totalBeforeL2))
    const expected_E = E_coll.add(E_coll.mul(th.applyLiquidationFee(F_coll)).div(totalBeforeL2))
    assert.isAtMost(th.getDifference(alice_Coll, expected_A), 1000)
    assert.isAtMost(th.getDifference(bob_Coll, expected_B), 1000)
    assert.isAtMost(th.getDifference(dennis_Coll, expected_D), 1000)
    assert.isAtMost(th.getDifference(erin_Coll, expected_E), 1000)

    const entireSystemColl = await wstETHTokenMock.balanceOf(positionManager.address)
    assert.equal(entireSystemColl.toString(), A_coll.add(B_coll).add(D_coll).add(E_coll).add(th.applyLiquidationFee(C_coll.add(F_coll))).toString())

    // check R gas compensation
    assert.equal((await rToken.balanceOf(owner)).toString(), dec(400, 18))
  })
  ////

  it("redistribution: Sequence of alternate opening/liquidation: final surviving position has ETH from all previously liquidated positions", async () => {
    // A, B  open positions
    const { collateral: A_coll } = await openPosition({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll } = await openPosition({ ICR: toBN(dec(400, 16)), extraParams: { from: bob } })

    // Price drops to 1 $/E
    await priceFeed.setPrice(dec(1, 18))

    // L1: A liquidated
    const txA = await positionManager.liquidate(alice)
    assert.isTrue(txA.receipt.status)
    assert.isFalse(await sortedPositions.contains(alice))

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(200, 18))
    // C, opens position
    const { collateral: C_coll } = await openPosition({ ICR: toBN(dec(210, 16)), extraParams: { from: carol } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(1, 18))

    // L2: B Liquidated
    const txB = await positionManager.liquidate(bob)
    assert.isTrue(txB.receipt.status)
    assert.isFalse(await sortedPositions.contains(bob))

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(200, 18))
    // D opens position
    const { collateral: D_coll } = await openPosition({ ICR: toBN(dec(210, 16)), extraParams: { from: dennis } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(1, 18))

    // L3: C Liquidated
    const txC = await positionManager.liquidate(carol)
    assert.isTrue(txC.receipt.status)
    assert.isFalse(await sortedPositions.contains(carol))

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(200, 18))
    // E opens position
    const { collateral: E_coll } = await openPosition({ ICR: toBN(dec(210, 16)), extraParams: { from: erin } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(1, 18))

    // L4: D Liquidated
    const txD = await positionManager.liquidate(dennis)
    assert.isTrue(txD.receipt.status)
    assert.isFalse(await sortedPositions.contains(dennis))

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(200, 18))
    // F opens position
    const { collateral: F_coll } = await openPosition({ ICR: toBN(dec(210, 16)), extraParams: { from: freddy } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(1, 18))

    // L5: E Liquidated
    const txE = await positionManager.liquidate(erin)
    assert.isTrue(txE.receipt.status)
    assert.isFalse(await sortedPositions.contains(erin))

    // Get entire coll of A, B, D, E and F
    const alice_Coll = ((await positionManager.positions(alice))[1]
      .add(await positionManager.getPendingCollateralTokenReward(alice)))
      .toString()
    const bob_Coll = ((await positionManager.positions(bob))[1]
      .add(await positionManager.getPendingCollateralTokenReward(bob)))
      .toString()
    const carol_Coll = ((await positionManager.positions(carol))[1]
      .add(await positionManager.getPendingCollateralTokenReward(carol)))
      .toString()
    const dennis_Coll = ((await positionManager.positions(dennis))[1]
      .add(await positionManager.getPendingCollateralTokenReward(dennis)))
      .toString()
    const erin_Coll = ((await positionManager.positions(erin))[1]
      .add(await positionManager.getPendingCollateralTokenReward(erin)))
      .toString()

    const freddy_rawColl = (await positionManager.positions(freddy))[1].toString()
    const freddy_ETHReward = (await positionManager.getPendingCollateralTokenReward(freddy)).toString()

    /* Expected collateral:
     A-E should have been liquidated
     position F should have acquired all ETH in the system: 1 ETH initial coll, and 0.995^5+0.995^4+0.995^3+0.995^2+0.995 from rewards = 5.925 ETH
    */
    assert.isAtMost(th.getDifference(alice_Coll, '0'), 1000)
    assert.isAtMost(th.getDifference(bob_Coll, '0'), 1000)
    assert.isAtMost(th.getDifference(carol_Coll, '0'), 1000)
    assert.isAtMost(th.getDifference(dennis_Coll, '0'), 1000)
    assert.isAtMost(th.getDifference(erin_Coll, '0'), 1000)

    assert.isAtMost(th.getDifference(freddy_rawColl, F_coll), 1000)
    const gainedETH = th.applyLiquidationFee(
      E_coll.add(th.applyLiquidationFee(
        D_coll.add(th.applyLiquidationFee(
          C_coll.add(th.applyLiquidationFee(
            B_coll.add(th.applyLiquidationFee(A_coll))
          ))
        ))
      ))
    )
    assert.isAtMost(th.getDifference(freddy_ETHReward, gainedETH), 1000)

    const entireSystemColl = await wstETHTokenMock.balanceOf(positionManager.address)
    assert.isAtMost(th.getDifference(entireSystemColl, F_coll.add(gainedETH)), 1000)

    // check R gas compensation
    assert.equal((await rToken.balanceOf(owner)).toString(), dec(1000, 18))
  })

  // ---Position adds collateral ---

  // Test based on scenario in: https://docs.google.com/spreadsheets/d/1F5p3nZy749K5jwO-bwJeTsRoY7ewMfWIQ3QHtokxqzo/edit?usp=sharing
  it("redistribution: A,B,C,D,E open. Liq(A). B adds coll. Liq(C). B and D have correct coll and debt", async () => {
    // A, B, C, D, E open positions
    const { collateral: A_coll } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(100000, 18), extraParams: { from: A } })
    const { collateral: B_coll } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(100000, 18), extraParams: { from: B } })
    const { collateral: C_coll } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(100000, 18), extraParams: { from: C } })
    const { collateral: D_coll } = await openPosition({ ICR: toBN(dec(20000, 16)), extraRAmount: dec(10, 18), extraParams: { from: D } })
    const { collateral: E_coll } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(100000, 18), extraParams: { from: E } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 18))

    // Liquidate A
    // console.log(`ICR A: ${await positionManager.getCurrentICR(A, price)}`)
    const txA = await positionManager.liquidate(A)
    assert.isTrue(txA.receipt.status)
    assert.isFalse(await sortedPositions.contains(A))

    // Check entireColl for each position:
    const B_entireColl_1 = (await th.getEntireCollAndDebt(contracts, B)).entireColl
    const C_entireColl_1 = (await th.getEntireCollAndDebt(contracts, C)).entireColl
    const D_entireColl_1 = (await th.getEntireCollAndDebt(contracts, D)).entireColl
    const E_entireColl_1 = (await th.getEntireCollAndDebt(contracts, E)).entireColl

    const totalCollAfterL1 = B_coll.add(C_coll).add(D_coll).add(E_coll)
    const B_collAfterL1 = B_coll.add(th.applyLiquidationFee(A_coll).mul(B_coll).div(totalCollAfterL1))
    const C_collAfterL1 = C_coll.add(th.applyLiquidationFee(A_coll).mul(C_coll).div(totalCollAfterL1))
    const D_collAfterL1 = D_coll.add(th.applyLiquidationFee(A_coll).mul(D_coll).div(totalCollAfterL1))
    const E_collAfterL1 = E_coll.add(th.applyLiquidationFee(A_coll).mul(E_coll).div(totalCollAfterL1))
    assert.isAtMost(getDifference(B_entireColl_1, B_collAfterL1), 1e8)
    assert.isAtMost(getDifference(C_entireColl_1, C_collAfterL1), 1e8)
    assert.isAtMost(getDifference(D_entireColl_1, D_collAfterL1), 1e8)
    assert.isAtMost(getDifference(E_entireColl_1, E_collAfterL1), 1e8)

    // Bob adds 1 ETH to his position
    const addedColl1 = toBN(dec(1, 'ether'))
    await priceFeed.setPrice(dec(200, 18))
    wstETHTokenMock.approve(positionManager.address, addedColl1, { from: B})
    await positionManager.addColl(B, B, addedColl1, { from: B })
    await priceFeed.setPrice(dec(100, 18))

    // Liquidate C
    const txC = await positionManager.liquidate(C)
    assert.isTrue(txC.receipt.status)
    assert.isFalse(await sortedPositions.contains(C))

    const B_entireColl_2 = (await th.getEntireCollAndDebt(contracts, B)).entireColl
    const D_entireColl_2 = (await th.getEntireCollAndDebt(contracts, D)).entireColl
    const E_entireColl_2 = (await th.getEntireCollAndDebt(contracts, E)).entireColl

    const totalCollAfterL2 = B_collAfterL1.add(addedColl1).add(D_collAfterL1).add(E_collAfterL1)
    const B_collAfterL2 = B_collAfterL1.add(addedColl1).add(th.applyLiquidationFee(C_collAfterL1).mul(B_collAfterL1.add(addedColl1)).div(totalCollAfterL2))
    const D_collAfterL2 = D_collAfterL1.add(th.applyLiquidationFee(C_collAfterL1).mul(D_collAfterL1).div(totalCollAfterL2))
    const E_collAfterL2 = E_collAfterL1.add(th.applyLiquidationFee(C_collAfterL1).mul(E_collAfterL1).div(totalCollAfterL2))
    // console.log(`D_entireColl_2: ${D_entireColl_2}`)
    // console.log(`E_entireColl_2: ${E_entireColl_2}`)
    //assert.isAtMost(getDifference(B_entireColl_2, B_collAfterL2), 1e8)
    assert.isAtMost(getDifference(D_entireColl_2, D_collAfterL2), 1e8)
    assert.isAtMost(getDifference(E_entireColl_2, E_collAfterL2), 1e8)

    // Bob adds 1 ETH to his position
    const addedColl2 = toBN(dec(1, 'ether'))
    await priceFeed.setPrice(dec(200, 18))
    wstETHTokenMock.approve(positionManager.address, addedColl2, { from: B})
    await positionManager.addColl(B, B, addedColl2, { from: B })
    await priceFeed.setPrice(dec(100, 18))

    // Liquidate E
    const txE = await positionManager.liquidate(E)
    assert.isTrue(txE.receipt.status)
    assert.isFalse(await sortedPositions.contains(E))

    const totalCollAfterL3 = B_collAfterL2.add(addedColl2).add(D_collAfterL2)
    const B_collAfterL3 = B_collAfterL2.add(addedColl2).add(th.applyLiquidationFee(E_collAfterL2).mul(B_collAfterL2.add(addedColl2)).div(totalCollAfterL3))
    const D_collAfterL3 = D_collAfterL2.add(th.applyLiquidationFee(E_collAfterL2).mul(D_collAfterL2).div(totalCollAfterL3))

    const B_entireColl_3 = (await th.getEntireCollAndDebt(contracts, B)).entireColl
    const D_entireColl_3 = (await th.getEntireCollAndDebt(contracts, D)).entireColl

    const diff_entireColl_B = getDifference(B_entireColl_3, B_collAfterL3)
    const diff_entireColl_D = getDifference(D_entireColl_3, D_collAfterL3)

    assert.isAtMost(diff_entireColl_B, 1e8)
    assert.isAtMost(diff_entireColl_D, 1e8)
  })

  it("redistribution: A,B,C Open. Liq(C). B adds coll. Liq(A). B acquires all coll and debt", async () => {
    // A, B, C open positions
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openPosition({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(110, 18), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(110, 18), extraParams: { from: carol } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 18))

    // Liquidate Carol
    const txC = await positionManager.liquidate(carol)
    assert.isTrue(txC.receipt.status)
    assert.isFalse(await sortedPositions.contains(carol))

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(200, 18))

    //Bob adds ETH to his position
    const addedColl = toBN(dec(1, 'ether'))
    wstETHTokenMock.approve(positionManager.address, addedColl, { from: bob})
    await positionManager.addColl(bob, bob, addedColl, { from: bob })

    // Alice withdraws R
    await positionManager.withdrawR(th._100pct, await getNetBorrowingAmount(A_totalDebt), alice, alice, { from: alice })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 18))

    // Liquidate Alice
    const txA = await positionManager.liquidate(alice)
    assert.isTrue(txA.receipt.status)
    assert.isFalse(await sortedPositions.contains(alice))

    // Expect Bob now holds all Ether and rDebt in the system: 2 + 0.4975+0.4975*0.995+0.995 Ether and 110*3 R (10 each for gas compensation)
    const bob_Coll = ((await positionManager.positions(bob))[1]
      .add(await positionManager.getPendingCollateralTokenReward(bob)))
      .toString()

    const bob_RDebt = ((await positionManager.positions(bob))[0]
      .add(await positionManager.getPendingRDebtReward(bob)))
      .toString()

    const expected_B_coll = B_coll
          .add(addedColl)
          .add(th.applyLiquidationFee(A_coll))
          .add(th.applyLiquidationFee(C_coll).mul(B_coll).div(A_coll.add(B_coll)))
          .add(th.applyLiquidationFee(th.applyLiquidationFee(C_coll).mul(A_coll).div(A_coll.add(B_coll))))
    assert.isAtMost(th.getDifference(bob_Coll, expected_B_coll), 1000)
    assert.isAtMost(th.getDifference(bob_RDebt, A_totalDebt.mul(toBN(2)).add(B_totalDebt).add(C_totalDebt)), 1000)
  })

  it("redistribution: A,B,C Open. Liq(C). B tops up coll. D Opens. Liq(D). Distributes correct rewards.", async () => {
    // A, B, C open positions
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openPosition({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(110, 18), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(110, 18), extraParams: { from: carol } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 18))

    // Liquidate Carol
    const txC = await positionManager.liquidate(carol)
    assert.isTrue(txC.receipt.status)
    assert.isFalse(await sortedPositions.contains(carol))

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(200, 18))

    //Bob adds ETH to his position
    const addedColl = toBN(dec(1, 'ether'))
    wstETHTokenMock.approve(positionManager.address, addedColl, { from: bob})
    await positionManager.addColl(bob, bob, addedColl, { from: bob })

    // D opens position
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(110, 18), extraParams: { from: dennis } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 18))

    // Liquidate D
    const txA = await positionManager.liquidate(dennis)
    assert.isTrue(txA.receipt.status)
    assert.isFalse(await sortedPositions.contains(dennis))

    /* Bob rewards:
     L1: 1/2*0.995 ETH, 55 R
     L2: (2.4975/3.995)*0.995 = 0.622 ETH , 110*(2.4975/3.995)= 68.77 rDebt

    coll: 3.1195 ETH
    debt: 233.77 rDebt

     Alice rewards:
    L1 1/2*0.995 ETH, 55 R
    L2 (1.4975/3.995)*0.995 = 0.3730 ETH, 110*(1.4975/3.995) = 41.23 rDebt

    coll: 1.8705 ETH
    debt: 146.23 rDebt

    totalColl: 4.99 ETH
    totalDebt 380 R (includes 50 each for gas compensation)
    */
    const bob_Coll = ((await positionManager.positions(bob))[1]
      .add(await positionManager.getPendingCollateralTokenReward(bob)))
      .toString()

    const bob_RDebt = ((await positionManager.positions(bob))[0]
      .add(await positionManager.getPendingRDebtReward(bob)))
      .toString()

    const alice_Coll = ((await positionManager.positions(alice))[1]
      .add(await positionManager.getPendingCollateralTokenReward(alice)))
      .toString()

    const alice_RDebt = ((await positionManager.positions(alice))[0]
      .add(await positionManager.getPendingRDebtReward(alice)))
      .toString()

    const totalCollAfterL1 = A_coll.add(B_coll).add(addedColl).add(th.applyLiquidationFee(C_coll))
    const B_collAfterL1 = B_coll.add(B_coll.mul(th.applyLiquidationFee(C_coll)).div(A_coll.add(B_coll))).add(addedColl)
    const expected_B_coll = B_collAfterL1.add(B_collAfterL1.mul(th.applyLiquidationFee(D_coll)).div(totalCollAfterL1))
    const expected_B_debt = B_totalDebt
          .add(B_coll.mul(C_totalDebt).div(A_coll.add(B_coll)))
          .add(B_collAfterL1.mul(D_totalDebt).div(totalCollAfterL1))
    assert.isAtMost(th.getDifference(bob_Coll, expected_B_coll), 1000)
    assert.isAtMost(th.getDifference(bob_RDebt, expected_B_debt), 10000)

    const A_collAfterL1 = A_coll.add(A_coll.mul(th.applyLiquidationFee(C_coll)).div(A_coll.add(B_coll)))
    const expected_A_coll = A_collAfterL1.add(A_collAfterL1.mul(th.applyLiquidationFee(D_coll)).div(totalCollAfterL1))
    const expected_A_debt = A_totalDebt
          .add(A_coll.mul(C_totalDebt).div(A_coll.add(B_coll)))
          .add(A_collAfterL1.mul(D_totalDebt).div(totalCollAfterL1))
    assert.isAtMost(th.getDifference(alice_Coll, expected_A_coll), 1000)
    assert.isAtMost(th.getDifference(alice_RDebt, expected_A_debt), 10000)

    // check R gas compensation
    assert.equal((await rToken.balanceOf(owner)).toString(), dec(400, 18))
  })

  it("redistribution: Position with the majority stake tops up. A,B,C, D open. Liq(D). C tops up. E Enters, Liq(E). Distributes correct rewards", async () => {
    const _998_Ether = toBN('998000000000000000000')
    // A, B, C, D open positions
    const { collateral: A_coll } = await openPosition({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll } = await openPosition({ ICR: toBN(dec(400, 16)), extraRAmount: dec(110, 18), extraParams: { from: bob } })
    wstETHTokenMock.approve(positionManager.address, _998_Ether, { from: carol})
    const { collateral: C_coll } = await openPosition({ extraRAmount: dec(110, 18), amount: _998_Ether, extraParams: { from: carol } })
    wstETHTokenMock.approve(positionManager.address, dec(1000, 'ether'), { from: carol})
    const { collateral: D_coll } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(110, 18), amount: dec(1000, 'ether'), extraParams: { from: dennis } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 18))

    // Liquidate Dennis
    const txD = await positionManager.liquidate(dennis)
    assert.isTrue(txD.receipt.status)
    assert.isFalse(await sortedPositions.contains(dennis))

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(200, 18))

    // Expected rewards:  alice: 1 ETH, bob: 1 ETH, carol: 998 ETH
    const alice_ETHReward_1 = await positionManager.getPendingCollateralTokenReward(alice)
    const bob_ETHReward_1 = await positionManager.getPendingCollateralTokenReward(bob)
    const carol_ETHReward_1 = await positionManager.getPendingCollateralTokenReward(carol)

    //Expect 1000 + 1000*0.995 ETH in system now
    const entireSystemColl_1 = await wstETHTokenMock.balanceOf(positionManager.address)
    assert.equal(entireSystemColl_1.toString(), A_coll.add(B_coll).add(C_coll).add(th.applyLiquidationFee(D_coll)).toString())

    const totalColl = A_coll.add(B_coll).add(C_coll)
    th.assertIsApproximatelyEqual(alice_ETHReward_1.toString(), th.applyLiquidationFee(D_coll).mul(A_coll).div(totalColl))
    th.assertIsApproximatelyEqual(bob_ETHReward_1.toString(), th.applyLiquidationFee(D_coll).mul(B_coll).div(totalColl))
    th.assertIsApproximatelyEqual(carol_ETHReward_1.toString(), th.applyLiquidationFee(D_coll).mul(C_coll).div(totalColl))

    //Carol adds 1 ETH to her position, brings it to 1992.01 total coll
    const C_addedColl = toBN(dec(1, 'ether'))
    wstETHTokenMock.approve(positionManager.address, dec(1, 'ether'), { from: carol})
    await positionManager.addColl(carol, carol, dec(1, 'ether'), { from: carol })

    //Expect 1996 ETH in system now
    const entireSystemColl_2 = await wstETHTokenMock.balanceOf(positionManager.address)
    th.assertIsApproximatelyEqual(entireSystemColl_2, totalColl.add(th.applyLiquidationFee(D_coll)).add(C_addedColl))

    // E opens with another 1996 ETH
    wstETHTokenMock.approve(positionManager.address, entireSystemColl_2, { from: erin})
    const { collateral: E_coll } = await openPosition({ ICR: toBN(dec(200, 16)), amount: entireSystemColl_2, extraParams: { from: erin } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 18))

    // Liquidate Erin
    const txE = await positionManager.liquidate(erin)
    assert.isTrue(txE.receipt.status)
    assert.isFalse(await sortedPositions.contains(erin))

    /* Expected ETH rewards:
     Carol = 1992.01/1996 * 1996*0.995 = 1982.05 ETH
     Alice = 1.995/1996 * 1996*0.995 = 1.985025 ETH
     Bob = 1.995/1996 * 1996*0.995 = 1.985025 ETH

    therefore, expected total collateral:

    Carol = 1991.01 + 1991.01 = 3974.06
    Alice = 1.995 + 1.985025 = 3.980025 ETH
    Bob = 1.995 + 1.985025 = 3.980025 ETH

    total = 3982.02 ETH
    */

    const alice_Coll = ((await positionManager.positions(alice))[1]
      .add(await positionManager.getPendingCollateralTokenReward(alice)))
      .toString()

    const bob_Coll = ((await positionManager.positions(bob))[1]
      .add(await positionManager.getPendingCollateralTokenReward(bob)))
      .toString()

    const carol_Coll = ((await positionManager.positions(carol))[1]
      .add(await positionManager.getPendingCollateralTokenReward(carol)))
      .toString()

    const totalCollAfterL1 = A_coll.add(B_coll).add(C_coll).add(th.applyLiquidationFee(D_coll)).add(C_addedColl)
    const A_collAfterL1 = A_coll.add(A_coll.mul(th.applyLiquidationFee(D_coll)).div(A_coll.add(B_coll).add(C_coll)))
    const expected_A_coll = A_collAfterL1.add(A_collAfterL1.mul(th.applyLiquidationFee(E_coll)).div(totalCollAfterL1))
    const B_collAfterL1 = B_coll.add(B_coll.mul(th.applyLiquidationFee(D_coll)).div(A_coll.add(B_coll).add(C_coll)))
    const expected_B_coll = B_collAfterL1.add(B_collAfterL1.mul(th.applyLiquidationFee(E_coll)).div(totalCollAfterL1))
    const C_collAfterL1 = C_coll.add(C_coll.mul(th.applyLiquidationFee(D_coll)).div(A_coll.add(B_coll).add(C_coll))).add(C_addedColl)
    const expected_C_coll = C_collAfterL1.add(C_collAfterL1.mul(th.applyLiquidationFee(E_coll)).div(totalCollAfterL1))

    assert.isAtMost(th.getDifference(alice_Coll, expected_A_coll), 1000)
    assert.isAtMost(th.getDifference(bob_Coll, expected_B_coll), 1000)
    assert.isAtMost(th.getDifference(carol_Coll, expected_C_coll), 1000)

    //Expect 3982.02 ETH in system now
    const entireSystemColl_3 = await wstETHTokenMock.balanceOf(positionManager.address)
    th.assertIsApproximatelyEqual(entireSystemColl_3, totalCollAfterL1.add(th.applyLiquidationFee(E_coll)))

    // check R gas compensation
    th.assertIsApproximatelyEqual((await rToken.balanceOf(owner)).toString(), dec(400, 18))
  })

  it("redistribution: Position with the majority stake tops up. A,B,C, D open. Liq(D). A, B, C top up. E Enters, Liq(E). Distributes correct rewards", async () => {
    const _998_Ether = toBN('998000000000000000000')
    // A, B, C open positions
    const { collateral: A_coll } = await openPosition({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll } = await openPosition({ ICR: toBN(dec(400, 16)), extraRAmount: dec(110, 18), extraParams: { from: bob } })
    wstETHTokenMock.approve(positionManager.address, _998_Ether, { from: carol})
    const { collateral: C_coll } = await openPosition({ extraRAmount: dec(110, 18), amount: _998_Ether, extraParams: { from: carol } })
    wstETHTokenMock.approve(positionManager.address, dec(1000, 'ether'), { from: dennis})
    const { collateral: D_coll } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(110, 18), amount: dec(1000, 'ether'), extraParams: { from: dennis } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 18))

    // Liquidate Dennis
    const txD = await positionManager.liquidate(dennis)
    assert.isTrue(txD.receipt.status)
    assert.isFalse(await sortedPositions.contains(dennis))

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(200, 18))

    // Expected rewards:  alice: 1 ETH, bob: 1 ETH, carol: 998 ETH (*0.995)
    const alice_ETHReward_1 = await positionManager.getPendingCollateralTokenReward(alice)
    const bob_ETHReward_1 = await positionManager.getPendingCollateralTokenReward(bob)
    const carol_ETHReward_1 = await positionManager.getPendingCollateralTokenReward(carol)

    //Expect 1995 ETH in system now
    const entireSystemColl_1 = await wstETHTokenMock.balanceOf(positionManager.address)
    assert.equal(entireSystemColl_1.toString(), A_coll.add(B_coll).add(C_coll).add(th.applyLiquidationFee(D_coll)).toString())


    const totalColl = A_coll.add(B_coll).add(C_coll)
    th.assertIsApproximatelyEqual(alice_ETHReward_1.toString(), th.applyLiquidationFee(D_coll).mul(A_coll).div(totalColl))
    th.assertIsApproximatelyEqual(bob_ETHReward_1.toString(), th.applyLiquidationFee(D_coll).mul(B_coll).div(totalColl))
    th.assertIsApproximatelyEqual(carol_ETHReward_1.toString(), th.applyLiquidationFee(D_coll).mul(C_coll).div(totalColl))

    /* Alice, Bob, Carol each adds 1 ETH to their positions,
    bringing them to 2.995, 2.995, 1992.01 total coll each. */

    const addedColl = toBN(dec(1, 'ether'))
    wstETHTokenMock.approve(positionManager.address, addedColl, { from: alice})
    await positionManager.addColl(alice, alice, addedColl, { from: alice })
    wstETHTokenMock.approve(positionManager.address, addedColl, { from: bob})
    await positionManager.addColl(bob, bob, addedColl, { from: bob })
    wstETHTokenMock.approve(positionManager.address, addedColl, { from: carol})
    await positionManager.addColl(carol, carol, addedColl, { from: carol })

    //Expect 1998 ETH in system now
    const entireSystemColl_2 = await wstETHTokenMock.balanceOf(positionManager.address)
    th.assertIsApproximatelyEqual(entireSystemColl_2, totalColl.add(th.applyLiquidationFee(D_coll)).add(addedColl.mul(toBN(3))))


    // E opens with another 1998 ETH
    wstETHTokenMock.approve(positionManager.address, entireSystemColl_2, { from: erin})
    const { collateral: E_coll } = await openPosition({ ICR: toBN(dec(200, 16)), amount: entireSystemColl_2, extraParams: { from: erin } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 18))

    // Liquidate Erin
    const txE = await positionManager.liquidate(erin)
    assert.isTrue(txE.receipt.status)
    assert.isFalse(await sortedPositions.contains(erin))

    /* Expected ETH rewards:
     Carol = 1992.01/1998 * 1998*0.995 = 1982.04995 ETH
     Alice = 2.995/1998 * 1998*0.995 = 2.980025 ETH
     Bob = 2.995/1998 * 1998*0.995 = 2.980025 ETH

    therefore, expected total collateral:

    Carol = 1992.01 + 1982.04995 = 3974.05995
    Alice = 2.995 + 2.980025 = 5.975025 ETH
    Bob = 2.995 + 2.980025 = 5.975025 ETH

    total = 3986.01 ETH
    */

    const alice_Coll = ((await positionManager.positions(alice))[1]
      .add(await positionManager.getPendingCollateralTokenReward(alice)))
      .toString()

    const bob_Coll = ((await positionManager.positions(bob))[1]
      .add(await positionManager.getPendingCollateralTokenReward(bob)))
      .toString()

    const carol_Coll = ((await positionManager.positions(carol))[1]
      .add(await positionManager.getPendingCollateralTokenReward(carol)))
      .toString()

    const totalCollAfterL1 = A_coll.add(B_coll).add(C_coll).add(th.applyLiquidationFee(D_coll)).add(addedColl.mul(toBN(3)))
    const A_collAfterL1 = A_coll.add(A_coll.mul(th.applyLiquidationFee(D_coll)).div(A_coll.add(B_coll).add(C_coll))).add(addedColl)
    const expected_A_coll = A_collAfterL1.add(A_collAfterL1.mul(th.applyLiquidationFee(E_coll)).div(totalCollAfterL1))
    const B_collAfterL1 = B_coll.add(B_coll.mul(th.applyLiquidationFee(D_coll)).div(A_coll.add(B_coll).add(C_coll))).add(addedColl)
    const expected_B_coll = B_collAfterL1.add(B_collAfterL1.mul(th.applyLiquidationFee(E_coll)).div(totalCollAfterL1))
    const C_collAfterL1 = C_coll.add(C_coll.mul(th.applyLiquidationFee(D_coll)).div(A_coll.add(B_coll).add(C_coll))).add(addedColl)
    const expected_C_coll = C_collAfterL1.add(C_collAfterL1.mul(th.applyLiquidationFee(E_coll)).div(totalCollAfterL1))

    assert.isAtMost(th.getDifference(alice_Coll, expected_A_coll), 1000)
    assert.isAtMost(th.getDifference(bob_Coll, expected_B_coll), 1000)
    assert.isAtMost(th.getDifference(carol_Coll, expected_C_coll), 1000)

    //Expect 3986.01 ETH in system now
    const entireSystemColl_3 = await wstETHTokenMock.balanceOf(positionManager.address)
    th.assertIsApproximatelyEqual(entireSystemColl_3, totalCollAfterL1.add(th.applyLiquidationFee(E_coll)))


    // check R gas compensation
    th.assertIsApproximatelyEqual((await rToken.balanceOf(owner)).toString(), dec(400, 18))
  })

  // --- Position withdraws collateral ---

  it("redistribution: A,B,C Open. Liq(C). B withdraws coll. Liq(A). B acquires all coll and debt", async () => {
    // A, B, C open positions
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openPosition({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(110, 18), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(110, 18), extraParams: { from: carol } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 18))

    // Liquidate Carol
    const txC = await positionManager.liquidate(carol)
    assert.isTrue(txC.receipt.status)
    assert.isFalse(await sortedPositions.contains(carol))

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(200, 18))

    //Bob withdraws 0.5 ETH from his position
    const withdrawnColl = toBN(dec(500, 'finney'))
    await positionManager.withdrawColl(withdrawnColl, bob, bob, { from: bob })

    // Alice withdraws R
    await positionManager.withdrawR(th._100pct, await getNetBorrowingAmount(A_totalDebt), alice, alice, { from: alice })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 18))

    // Liquidate Alice
    const txA = await positionManager.liquidate(alice)
    assert.isTrue(txA.receipt.status)
    assert.isFalse(await sortedPositions.contains(alice))

    // Expect Bob now holds all Ether and rDebt in the system: 2.5 Ether and 300 R
    // 1 + 0.995/2 - 0.5 + 1.4975*0.995
    const bob_Coll = ((await positionManager.positions(bob))[1]
      .add(await positionManager.getPendingCollateralTokenReward(bob)))
      .toString()

    const bob_RDebt = ((await positionManager.positions(bob))[0]
      .add(await positionManager.getPendingRDebtReward(bob)))
      .toString()

    const expected_B_coll = B_coll
          .sub(withdrawnColl)
          .add(th.applyLiquidationFee(A_coll))
          .add(th.applyLiquidationFee(C_coll).mul(B_coll).div(A_coll.add(B_coll)))
          .add(th.applyLiquidationFee(th.applyLiquidationFee(C_coll).mul(A_coll).div(A_coll.add(B_coll))))
    assert.isAtMost(th.getDifference(bob_Coll, expected_B_coll), 1000)
    assert.isAtMost(th.getDifference(bob_RDebt, A_totalDebt.mul(toBN(2)).add(B_totalDebt).add(C_totalDebt)), 1000)

    // check R gas compensation
    assert.equal((await rToken.balanceOf(owner)).toString(), dec(400, 18))
  })

  it("redistribution: A,B,C Open. Liq(C). B withdraws coll. D Opens. Liq(D). Distributes correct rewards.", async () => {
    // A, B, C open positions
    const { collateral: A_coll, totalDebt: A_totalDebt } = await openPosition({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll, totalDebt: B_totalDebt } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(110, 18), extraParams: { from: bob } })
    const { collateral: C_coll, totalDebt: C_totalDebt } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(110, 18), extraParams: { from: carol } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 18))

    // Liquidate Carol
    const txC = await positionManager.liquidate(carol)
    assert.isTrue(txC.receipt.status)
    assert.isFalse(await sortedPositions.contains(carol))

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(200, 18))

    //Bob  withdraws 0.5 ETH from his position
    const withdrawnColl = toBN(dec(500, 'finney'))
    await positionManager.withdrawColl(withdrawnColl, bob, bob, { from: bob })

    // D opens position
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(110, 18), extraParams: { from: dennis } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 18))

    // Liquidate D
    const txA = await positionManager.liquidate(dennis)
    assert.isTrue(txA.receipt.status)
    assert.isFalse(await sortedPositions.contains(dennis))

    /* Bob rewards:
     L1: 0.4975 ETH, 55 R
     L2: (0.9975/2.495)*0.995 = 0.3978 ETH , 110*(0.9975/2.495)= 43.98 rDebt

    coll: (1 + 0.4975 - 0.5 + 0.3968) = 1.3953 ETH
    debt: (110 + 55 + 43.98 = 208.98 rDebt

     Alice rewards:
    L1 0.4975, 55 R
    L2 (1.4975/2.495)*0.995 = 0.5972 ETH, 110*(1.4975/2.495) = 66.022 rDebt

    coll: (1 + 0.4975 + 0.5972) = 2.0947 ETH
    debt: (50 + 55 + 66.022) = 171.022 R Debt

    totalColl: 3.49 ETH
    totalDebt 380 R (Includes 50 in each position for gas compensation)
    */
    const bob_Coll = ((await positionManager.positions(bob))[1]
      .add(await positionManager.getPendingCollateralTokenReward(bob)))
      .toString()

    const bob_RDebt = ((await positionManager.positions(bob))[0]
      .add(await positionManager.getPendingRDebtReward(bob)))
      .toString()

    const alice_Coll = ((await positionManager.positions(alice))[1]
      .add(await positionManager.getPendingCollateralTokenReward(alice)))
      .toString()

    const alice_RDebt = ((await positionManager.positions(alice))[0]
      .add(await positionManager.getPendingRDebtReward(alice)))
      .toString()

    const totalCollAfterL1 = A_coll.add(B_coll).sub(withdrawnColl).add(th.applyLiquidationFee(C_coll))
    const B_collAfterL1 = B_coll.add(B_coll.mul(th.applyLiquidationFee(C_coll)).div(A_coll.add(B_coll))).sub(withdrawnColl)
    const expected_B_coll = B_collAfterL1.add(B_collAfterL1.mul(th.applyLiquidationFee(D_coll)).div(totalCollAfterL1))
    const expected_B_debt = B_totalDebt
          .add(B_coll.mul(C_totalDebt).div(A_coll.add(B_coll)))
          .add(B_collAfterL1.mul(D_totalDebt).div(totalCollAfterL1))
    assert.isAtMost(th.getDifference(bob_Coll, expected_B_coll), 1000)
    assert.isAtMost(th.getDifference(bob_RDebt, expected_B_debt), 10000)

    const A_collAfterL1 = A_coll.add(A_coll.mul(th.applyLiquidationFee(C_coll)).div(A_coll.add(B_coll)))
    const expected_A_coll = A_collAfterL1.add(A_collAfterL1.mul(th.applyLiquidationFee(D_coll)).div(totalCollAfterL1))
    const expected_A_debt = A_totalDebt
          .add(A_coll.mul(C_totalDebt).div(A_coll.add(B_coll)))
          .add(A_collAfterL1.mul(D_totalDebt).div(totalCollAfterL1))
    assert.isAtMost(th.getDifference(alice_Coll, expected_A_coll), 1000)
    assert.isAtMost(th.getDifference(alice_RDebt, expected_A_debt), 10000)

    // check R gas compensation
    th.assertIsApproximatelyEqual((await rToken.balanceOf(owner)).toString(), dec(400, 18))
  })

  it("redistribution: Position with the majority stake withdraws. A,B,C,D open. Liq(D). C withdraws some coll. E Enters, Liq(E). Distributes correct rewards", async () => {
    const _998_Ether = toBN('998000000000000000000')
    // A, B, C, D open positions
    const { collateral: A_coll } = await openPosition({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll } = await openPosition({ ICR: toBN(dec(400, 16)), extraRAmount: dec(110, 18), extraParams: { from: bob } })
    wstETHTokenMock.approve(positionManager.address, _998_Ether, { from: carol})
    const { collateral: C_coll } = await openPosition({ extraRAmount: dec(110, 18), amount: _998_Ether, extraParams: { from: carol } })
    wstETHTokenMock.approve(positionManager.address, dec(1000, 'ether'), { from: dennis})
    const { collateral: D_coll } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(110, 18), amount: dec(1000, 'ether'), extraParams: { from: dennis } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 18))

    // Liquidate Dennis
    const txD = await positionManager.liquidate(dennis)
    assert.isTrue(txD.receipt.status)
    assert.isFalse(await sortedPositions.contains(dennis))

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(200, 18))

    // Expected rewards:  alice: 1 ETH, bob: 1 ETH, carol: 998 ETH (*0.995)
    const alice_ETHReward_1 = await positionManager.getPendingCollateralTokenReward(alice)
    const bob_ETHReward_1 = await positionManager.getPendingCollateralTokenReward(bob)
    const carol_ETHReward_1 = await positionManager.getPendingCollateralTokenReward(carol)

    //Expect 1995 ETH in system now
    const entireSystemColl_1 = await wstETHTokenMock.balanceOf(positionManager.address)
    th.assertIsApproximatelyEqual(entireSystemColl_1, A_coll.add(B_coll).add(C_coll).add(th.applyLiquidationFee(D_coll)))


    const totalColl = A_coll.add(B_coll).add(C_coll)
    th.assertIsApproximatelyEqual(alice_ETHReward_1.toString(), th.applyLiquidationFee(D_coll).mul(A_coll).div(totalColl))
    th.assertIsApproximatelyEqual(bob_ETHReward_1.toString(), th.applyLiquidationFee(D_coll).mul(B_coll).div(totalColl))
    th.assertIsApproximatelyEqual(carol_ETHReward_1.toString(), th.applyLiquidationFee(D_coll).mul(C_coll).div(totalColl))

    //Carol wthdraws 1 ETH from her position, brings it to 1990.01 total coll
    const C_withdrawnColl = toBN(dec(1, 'ether'))
    await positionManager.withdrawColl(C_withdrawnColl, carol, carol, { from: carol })

    //Expect 1994 ETH in system now
    const entireSystemColl_2 = await wstETHTokenMock.balanceOf(positionManager.address)
    th.assertIsApproximatelyEqual(entireSystemColl_2, totalColl.add(th.applyLiquidationFee(D_coll)).sub(C_withdrawnColl))


    // E opens with another 1994 ETH
    wstETHTokenMock.approve(positionManager.address, entireSystemColl_2, { from: erin})
    const { collateral: E_coll } = await openPosition({ ICR: toBN(dec(200, 16)), amount: entireSystemColl_2, extraParams: { from: erin } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 18))

    // Liquidate Erin
    const txE = await positionManager.liquidate(erin)
    assert.isTrue(txE.receipt.status)
    assert.isFalse(await sortedPositions.contains(erin))

    /* Expected ETH rewards:
     Carol = 1990.01/1994 * 1994*0.995 = 1980.05995 ETH
     Alice = 1.995/1994 * 1994*0.995 = 1.985025 ETH
     Bob = 1.995/1994 * 1994*0.995 = 1.985025 ETH

    therefore, expected total collateral:

    Carol = 1990.01 + 1980.05995 = 3970.06995
    Alice = 1.995 + 1.985025 = 3.980025 ETH
    Bob = 1.995 + 1.985025 = 3.980025 ETH

    total = 3978.03 ETH
    */

    const alice_Coll = ((await positionManager.positions(alice))[1]
      .add(await positionManager.getPendingCollateralTokenReward(alice)))
      .toString()

    const bob_Coll = ((await positionManager.positions(bob))[1]
      .add(await positionManager.getPendingCollateralTokenReward(bob)))
      .toString()

    const carol_Coll = ((await positionManager.positions(carol))[1]
      .add(await positionManager.getPendingCollateralTokenReward(carol)))
      .toString()

    const totalCollAfterL1 = A_coll.add(B_coll).add(C_coll).add(th.applyLiquidationFee(D_coll)).sub(C_withdrawnColl)
    const A_collAfterL1 = A_coll.add(A_coll.mul(th.applyLiquidationFee(D_coll)).div(A_coll.add(B_coll).add(C_coll)))
    const expected_A_coll = A_collAfterL1.add(A_collAfterL1.mul(th.applyLiquidationFee(E_coll)).div(totalCollAfterL1))
    const B_collAfterL1 = B_coll.add(B_coll.mul(th.applyLiquidationFee(D_coll)).div(A_coll.add(B_coll).add(C_coll)))
    const expected_B_coll = B_collAfterL1.add(B_collAfterL1.mul(th.applyLiquidationFee(E_coll)).div(totalCollAfterL1))
    const C_collAfterL1 = C_coll.add(C_coll.mul(th.applyLiquidationFee(D_coll)).div(A_coll.add(B_coll).add(C_coll))).sub(C_withdrawnColl)
    const expected_C_coll = C_collAfterL1.add(C_collAfterL1.mul(th.applyLiquidationFee(E_coll)).div(totalCollAfterL1))

    assert.isAtMost(th.getDifference(alice_Coll, expected_A_coll), 1000)
    assert.isAtMost(th.getDifference(bob_Coll, expected_B_coll), 1000)
    assert.isAtMost(th.getDifference(carol_Coll, expected_C_coll), 1000)

    //Expect 3978.03 ETH in system now
    const entireSystemColl_3 = await wstETHTokenMock.balanceOf(positionManager.address)
    th.assertIsApproximatelyEqual(entireSystemColl_3, totalCollAfterL1.add(th.applyLiquidationFee(E_coll)))


    // check R gas compensation
    assert.equal((await rToken.balanceOf(owner)).toString(), dec(400, 18))
  })

  it("redistribution: Position with the majority stake withdraws. A,B,C,D open. Liq(D). A, B, C withdraw. E Enters, Liq(E). Distributes correct rewards", async () => {
    const _998_Ether = toBN('998000000000000000000')
    // A, B, C, D open positions
    const { collateral: A_coll } = await openPosition({ ICR: toBN(dec(400, 16)), extraParams: { from: alice } })
    const { collateral: B_coll } = await openPosition({ ICR: toBN(dec(400, 16)), extraRAmount: dec(110, 18), extraParams: { from: bob } })
    wstETHTokenMock.approve(positionManager.address, _998_Ether, { from: carol})
    const { collateral: C_coll } = await openPosition({ extraRAmount: dec(110, 18), amount: _998_Ether, extraParams: { from: carol } })
    wstETHTokenMock.approve(positionManager.address, dec(1000, 'ether'), { from: dennis})
    const { collateral: D_coll } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(110, 18), amount: dec(1000, 'ether'), extraParams: { from: dennis } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 18))

    // Liquidate Dennis
    const txD = await positionManager.liquidate(dennis)
    assert.isTrue(txD.receipt.status)
    assert.isFalse(await sortedPositions.contains(dennis))

    // Price bounces back to 200 $/E
    await priceFeed.setPrice(dec(200, 18))

    // Expected rewards:  alice: 1 ETH, bob: 1 ETH, carol: 998 ETH (*0.995)
    const alice_ETHReward_1 = await positionManager.getPendingCollateralTokenReward(alice)
    const bob_ETHReward_1 = await positionManager.getPendingCollateralTokenReward(bob)
    const carol_ETHReward_1 = await positionManager.getPendingCollateralTokenReward(carol)

    //Expect 1995 ETH in system now
    const entireSystemColl_1 = await wstETHTokenMock.balanceOf(positionManager.address)
    th.assertIsApproximatelyEqual(entireSystemColl_1, A_coll.add(B_coll).add(C_coll).add(th.applyLiquidationFee(D_coll)))


    const totalColl = A_coll.add(B_coll).add(C_coll)
    th.assertIsApproximatelyEqual(alice_ETHReward_1.toString(), th.applyLiquidationFee(D_coll).mul(A_coll).div(totalColl))
    th.assertIsApproximatelyEqual(bob_ETHReward_1.toString(), th.applyLiquidationFee(D_coll).mul(B_coll).div(totalColl))
    th.assertIsApproximatelyEqual(carol_ETHReward_1.toString(), th.applyLiquidationFee(D_coll).mul(C_coll).div(totalColl))

    /* Alice, Bob, Carol each withdraw 0.5 ETH to their positions,
    bringing them to 1.495, 1.495, 1990.51 total coll each. */
    const withdrawnColl = toBN(dec(500, 'finney'))
    await positionManager.withdrawColl(withdrawnColl, alice, alice, { from: alice })
    await positionManager.withdrawColl(withdrawnColl, bob, bob, { from: bob })
    await positionManager.withdrawColl(withdrawnColl, carol, carol, { from: carol })

    const alice_Coll_1 = ((await positionManager.positions(alice))[1]
      .add(await positionManager.getPendingCollateralTokenReward(alice)))
      .toString()

    const bob_Coll_1 = ((await positionManager.positions(bob))[1]
      .add(await positionManager.getPendingCollateralTokenReward(bob)))
      .toString()

    const carol_Coll_1 = ((await positionManager.positions(carol))[1]
      .add(await positionManager.getPendingCollateralTokenReward(carol)))
      .toString()

    const totalColl_1 = A_coll.add(B_coll).add(C_coll)
    assert.isAtMost(th.getDifference(alice_Coll_1, A_coll.add(th.applyLiquidationFee(D_coll).mul(A_coll).div(totalColl_1)).sub(withdrawnColl)), 1000)
    assert.isAtMost(th.getDifference(bob_Coll_1, B_coll.add(th.applyLiquidationFee(D_coll).mul(B_coll).div(totalColl_1)).sub(withdrawnColl)), 1000)
    assert.isAtMost(th.getDifference(carol_Coll_1, C_coll.add(th.applyLiquidationFee(D_coll).mul(C_coll).div(totalColl_1)).sub(withdrawnColl)), 1000)

    //Expect 1993.5 ETH in system now
    const entireSystemColl_2 = await wstETHTokenMock.balanceOf(positionManager.address)
    th.assertIsApproximatelyEqual(entireSystemColl_2, totalColl.add(th.applyLiquidationFee(D_coll)).sub(withdrawnColl.mul(toBN(3))))


    // E opens with another 1993.5 ETH
    wstETHTokenMock.approve(positionManager.address, entireSystemColl_2, { from: erin})
    const { collateral: E_coll } = await openPosition({ ICR: toBN(dec(200, 16)), amount: entireSystemColl_2, extraParams: { from: erin } })

    // Price drops to 100 $/E
    await priceFeed.setPrice(dec(100, 18))

    // Liquidate Erin
    const txE = await positionManager.liquidate(erin)
    assert.isTrue(txE.receipt.status)
    assert.isFalse(await sortedPositions.contains(erin))

    /* Expected ETH rewards:
     Carol = 1990.51/1993.5 * 1993.5*0.995 = 1980.55745 ETH
     Alice = 1.495/1993.5 * 1993.5*0.995 = 1.487525 ETH
     Bob = 1.495/1993.5 * 1993.5*0.995 = 1.487525 ETH

    therefore, expected total collateral:

    Carol = 1990.51 + 1980.55745 = 3971.06745
    Alice = 1.495 + 1.487525 = 2.982525 ETH
    Bob = 1.495 + 1.487525 = 2.982525 ETH

    total = 3977.0325 ETH
    */

    const alice_Coll_2 = ((await positionManager.positions(alice))[1]
      .add(await positionManager.getPendingCollateralTokenReward(alice)))
      .toString()

    const bob_Coll_2 = ((await positionManager.positions(bob))[1]
      .add(await positionManager.getPendingCollateralTokenReward(bob)))
      .toString()

    const carol_Coll_2 = ((await positionManager.positions(carol))[1]
      .add(await positionManager.getPendingCollateralTokenReward(carol)))
      .toString()

    const totalCollAfterL1 = A_coll.add(B_coll).add(C_coll).add(th.applyLiquidationFee(D_coll)).sub(withdrawnColl.mul(toBN(3)))
    const A_collAfterL1 = A_coll.add(A_coll.mul(th.applyLiquidationFee(D_coll)).div(A_coll.add(B_coll).add(C_coll))).sub(withdrawnColl)
    const expected_A_coll = A_collAfterL1.add(A_collAfterL1.mul(th.applyLiquidationFee(E_coll)).div(totalCollAfterL1))
    const B_collAfterL1 = B_coll.add(B_coll.mul(th.applyLiquidationFee(D_coll)).div(A_coll.add(B_coll).add(C_coll))).sub(withdrawnColl)
    const expected_B_coll = B_collAfterL1.add(B_collAfterL1.mul(th.applyLiquidationFee(E_coll)).div(totalCollAfterL1))
    const C_collAfterL1 = C_coll.add(C_coll.mul(th.applyLiquidationFee(D_coll)).div(A_coll.add(B_coll).add(C_coll))).sub(withdrawnColl)
    const expected_C_coll = C_collAfterL1.add(C_collAfterL1.mul(th.applyLiquidationFee(E_coll)).div(totalCollAfterL1))

    assert.isAtMost(th.getDifference(alice_Coll_2, expected_A_coll), 1000)
    assert.isAtMost(th.getDifference(bob_Coll_2, expected_B_coll), 1000)
    assert.isAtMost(th.getDifference(carol_Coll_2, expected_C_coll), 1000)

    //Expect 3977.0325 ETH in system now
    const entireSystemColl_3 = await wstETHTokenMock.balanceOf(positionManager.address)
    th.assertIsApproximatelyEqual(entireSystemColl_3, totalCollAfterL1.add(th.applyLiquidationFee(E_coll)))

    // check R gas compensation
    assert.equal((await rToken.balanceOf(owner)).toString(), dec(400, 18))
  })

  // For calculations of correct values used in test, see scenario 1:
  // https://docs.google.com/spreadsheets/d/1F5p3nZy749K5jwO-bwJeTsRoY7ewMfWIQ3QHtokxqzo/edit?usp=sharing
  it("redistribution, all operations: A,B,C open. Liq(A). D opens. B adds, C withdraws. Liq(B). E & F open. D adds. Liq(F). Distributes correct rewards", async () => {
    // A, B, C open positions
    const { collateral: A_coll } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(100, 18), extraParams: { from: alice } })
    const { collateral: B_coll } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(100, 18), extraParams: { from: bob } })
    const { collateral: C_coll } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(100, 18), extraParams: { from: carol } })

    // Price drops to 1 $/E
    await priceFeed.setPrice(dec(1, 18))

    // Liquidate A
    const txA = await positionManager.liquidate(alice)
    assert.isTrue(txA.receipt.status)
    assert.isFalse(await sortedPositions.contains(alice))

    // Check rewards for B and C
    const B_pendingRewardsAfterL1 = th.applyLiquidationFee(A_coll).mul(B_coll).div(B_coll.add(C_coll))
    const C_pendingRewardsAfterL1 = th.applyLiquidationFee(A_coll).mul(C_coll).div(B_coll.add(C_coll))
    assert.isAtMost(th.getDifference(await positionManager.getPendingCollateralTokenReward(bob), B_pendingRewardsAfterL1), 1000000)
    assert.isAtMost(th.getDifference(await positionManager.getPendingCollateralTokenReward(carol), C_pendingRewardsAfterL1), 1000000)

    const totalStakesSnapshotAfterL1 = B_coll.add(C_coll)
    const totalCollateralSnapshotAfterL1 = totalStakesSnapshotAfterL1.add(th.applyLiquidationFee(A_coll))
    th.assertIsApproximatelyEqual(await positionManager.totalStakesSnapshot(), totalStakesSnapshotAfterL1)
    th.assertIsApproximatelyEqual(await positionManager.totalCollateralSnapshot(), totalCollateralSnapshotAfterL1)

    // Price rises to 1000
    await priceFeed.setPrice(dec(1000, 18))

    // D opens position
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(110, 18), extraParams: { from: dennis } })

    //Bob adds 1 ETH to his position
    const B_addedColl = toBN(dec(1, 'ether'))
    wstETHTokenMock.approve(positionManager.address, B_addedColl, { from: bob})
    await positionManager.addColl(bob, bob, B_addedColl, { from: bob })

    //Carol  withdraws 1 ETH from her position
    const C_withdrawnColl = toBN(dec(1, 'ether'))
    await positionManager.withdrawColl(C_withdrawnColl, carol, carol, { from: carol })

    const B_collAfterL1 = B_coll.add(B_pendingRewardsAfterL1).add(B_addedColl)
    const C_collAfterL1 = C_coll.add(C_pendingRewardsAfterL1).sub(C_withdrawnColl)

    // Price drops
    await priceFeed.setPrice(dec(1, 18))

    // Liquidate B
    const txB = await positionManager.liquidate(bob)
    assert.isTrue(txB.receipt.status)
    assert.isFalse(await sortedPositions.contains(bob))

    // Check rewards for C and D
    const C_pendingRewardsAfterL2 = C_collAfterL1.mul(th.applyLiquidationFee(B_collAfterL1)).div(C_collAfterL1.add(D_coll))
    const D_pendingRewardsAfterL2 = D_coll.mul(th.applyLiquidationFee(B_collAfterL1)).div(C_collAfterL1.add(D_coll))
    assert.isAtMost(th.getDifference(await positionManager.getPendingCollateralTokenReward(carol), C_pendingRewardsAfterL2), 1000000)
    assert.isAtMost(th.getDifference(await positionManager.getPendingCollateralTokenReward(dennis), D_pendingRewardsAfterL2), 1000000)

    const totalStakesSnapshotAfterL2 = totalStakesSnapshotAfterL1.add(D_coll.mul(totalStakesSnapshotAfterL1).div(totalCollateralSnapshotAfterL1)).sub(B_coll).sub(C_withdrawnColl.mul(totalStakesSnapshotAfterL1).div(totalCollateralSnapshotAfterL1))
    const defaultedAmountAfterL2 = th.applyLiquidationFee(B_coll.add(B_addedColl).add(B_pendingRewardsAfterL1)).add(C_pendingRewardsAfterL1)
    const totalCollateralSnapshotAfterL2 = C_coll.sub(C_withdrawnColl).add(D_coll).add(defaultedAmountAfterL2)
    th.assertIsApproximatelyEqual(await positionManager.totalStakesSnapshot(), totalStakesSnapshotAfterL2)
    th.assertIsApproximatelyEqual(await positionManager.totalCollateralSnapshot(), totalCollateralSnapshotAfterL2)

    // Price rises to 1000
    await priceFeed.setPrice(dec(1000, 18))

    // E and F open positions
    const { collateral: E_coll, totalDebt: E_totalDebt } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(110, 18), extraParams: { from: erin } })
    const { collateral: F_coll, totalDebt: F_totalDebt } = await openPosition({ ICR: toBN(dec(200, 16)), extraRAmount: dec(110, 18), extraParams: { from: freddy } })

    // D tops up
    const D_addedColl = toBN(dec(1, 'ether'))
    wstETHTokenMock.approve(positionManager.address, D_addedColl, { from: dennis})
    await positionManager.addColl(dennis, dennis, D_addedColl, { from: dennis })

    // Price drops to 1
    await priceFeed.setPrice(dec(1, 18))

    // Liquidate F
    const txF = await positionManager.liquidate(freddy)
    assert.isTrue(txF.receipt.status)
    assert.isFalse(await sortedPositions.contains(freddy))

    // Grab remaining positions' collateral
    const carol_rawColl = (await positionManager.positions(carol))[1].toString()
    const carol_pendingETHReward = (await positionManager.getPendingCollateralTokenReward(carol)).toString()

    const dennis_rawColl = (await positionManager.positions(dennis))[1].toString()
    const dennis_pendingETHReward = (await positionManager.getPendingCollateralTokenReward(dennis)).toString()

    const erin_rawColl = (await positionManager.positions(erin))[1].toString()
    const erin_pendingETHReward = (await positionManager.getPendingCollateralTokenReward(erin)).toString()

    // Check raw collateral of C, D, E
    const C_collAfterL2 = C_collAfterL1.add(C_pendingRewardsAfterL2)
    const D_collAfterL2 = D_coll.add(D_pendingRewardsAfterL2).add(D_addedColl)
    const totalCollForL3 = C_collAfterL2.add(D_collAfterL2).add(E_coll)
    const C_collAfterL3 = C_collAfterL2.add(C_collAfterL2.mul(th.applyLiquidationFee(F_coll)).div(totalCollForL3))
    const D_collAfterL3 = D_collAfterL2.add(D_collAfterL2.mul(th.applyLiquidationFee(F_coll)).div(totalCollForL3))
    const E_collAfterL3 = E_coll.add(E_coll.mul(th.applyLiquidationFee(F_coll)).div(totalCollForL3))
    assert.isAtMost(th.getDifference(carol_rawColl, C_collAfterL1), 1000)
    assert.isAtMost(th.getDifference(dennis_rawColl, D_collAfterL2), 1000000)
    assert.isAtMost(th.getDifference(erin_rawColl, E_coll), 1000)

    // Check pending ETH rewards of C, D, E
    assert.isAtMost(th.getDifference(carol_pendingETHReward, C_collAfterL3.sub(C_collAfterL1)), 1000000)
    assert.isAtMost(th.getDifference(dennis_pendingETHReward, D_collAfterL3.sub(D_collAfterL2)), 1000000)
    assert.isAtMost(th.getDifference(erin_pendingETHReward, E_collAfterL3.sub(E_coll)), 1000000)

    // Check system snapshots
    const totalStakesSnapshotAfterL3 = totalStakesSnapshotAfterL2.add(D_addedColl.add(E_coll).mul(totalStakesSnapshotAfterL2).div(totalCollateralSnapshotAfterL2))
    const totalCollateralSnapshotAfterL3 = C_coll.sub(C_withdrawnColl).add(D_coll).add(D_addedColl).add(E_coll).add(defaultedAmountAfterL2).add(th.applyLiquidationFee(F_coll))
    const totalStakesSnapshot = (await positionManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot = (await positionManager.totalCollateralSnapshot()).toString()
    th.assertIsApproximatelyEqual(totalStakesSnapshot, totalStakesSnapshotAfterL3)
    th.assertIsApproximatelyEqual(totalCollateralSnapshot, totalCollateralSnapshotAfterL3)

    // check R gas compensation
    assert.equal((await rToken.balanceOf(owner)).toString(), dec(600, 18))
  })

  // For calculations of correct values used in test, see scenario 2:
  // https://docs.google.com/spreadsheets/d/1F5p3nZy749K5jwO-bwJeTsRoY7ewMfWIQ3QHtokxqzo/edit?usp=sharing
  it("redistribution, all operations: A,B,C open. Liq(A). D opens. B adds, C withdraws. Liq(B). E & F open. D adds. Liq(F). Varying coll. Distributes correct rewards", async () => {
    /* A, B, C open positions.
    A: 450 ETH
    B: 8901 ETH
    C: 23.902 ETH
    */
    wstETHTokenMock.approve(positionManager.address, toBN('450000000000000000000'), { from: alice})
    const { collateral: A_coll } = await openPosition({ ICR: toBN(dec(90000, 16)), amount: toBN('450000000000000000000'), extraParams: { from: alice } })
    wstETHTokenMock.approve(positionManager.address, toBN('8901000000000000000000'), { from: bob})
    const { collateral: B_coll } = await openPosition({ ICR: toBN(dec(1800000, 16)), amount: toBN('8901000000000000000000'), extraParams: { from: bob } })
    wstETHTokenMock.approve(positionManager.address, toBN('23902000000000000000'), { from: carol})
    const { collateral: C_coll } = await openPosition({ ICR: toBN(dec(4600, 16)), amount: toBN('23902000000000000000'), extraParams: { from: carol } })

    // Price drops
    await priceFeed.setPrice('1')

    // Liquidate A
    const txA = await positionManager.liquidate(alice)
    assert.isTrue(txA.receipt.status)
    assert.isFalse(await sortedPositions.contains(alice))

    // Check rewards for B and C
    const B_pendingRewardsAfterL1 = th.applyLiquidationFee(A_coll).mul(B_coll).div(B_coll.add(C_coll))
    const C_pendingRewardsAfterL1 = th.applyLiquidationFee(A_coll).mul(C_coll).div(B_coll.add(C_coll))
    assert.isAtMost(th.getDifference(await positionManager.getPendingCollateralTokenReward(bob), B_pendingRewardsAfterL1), 1000000)
    assert.isAtMost(th.getDifference(await positionManager.getPendingCollateralTokenReward(carol), C_pendingRewardsAfterL1), 1000000)

    const totalStakesSnapshotAfterL1 = B_coll.add(C_coll)
    const totalCollateralSnapshotAfterL1 = totalStakesSnapshotAfterL1.add(th.applyLiquidationFee(A_coll))
    th.assertIsApproximatelyEqual(await positionManager.totalStakesSnapshot(), totalStakesSnapshotAfterL1)
    th.assertIsApproximatelyEqual(await positionManager.totalCollateralSnapshot(), totalCollateralSnapshotAfterL1)

    // Price rises
    await priceFeed.setPrice(dec(1, 27))

    // D opens position: 0.035 ETH
    wstETHTokenMock.approve(positionManager.address, toBN(dec(35, 15)), { from: dennis})
    const { collateral: D_coll, totalDebt: D_totalDebt } = await openPosition({ extraRAmount: dec(100, 18), amount: toBN(dec(35, 15)), extraParams: { from: dennis } })

    // Bob adds 11.33909 ETH to his position
    const B_addedColl = toBN('11339090000000000000')
    wstETHTokenMock.approve(positionManager.address, B_addedColl, { from: bob})
    await positionManager.addColl(bob, bob, B_addedColl, { from: bob })

    // Carol withdraws 15 ETH from her position
    const C_withdrawnColl = toBN(dec(15, 'ether'))
    await positionManager.withdrawColl(C_withdrawnColl, carol, carol, { from: carol })

    const B_collAfterL1 = B_coll.add(B_pendingRewardsAfterL1).add(B_addedColl)
    const C_collAfterL1 = C_coll.add(C_pendingRewardsAfterL1).sub(C_withdrawnColl)

    // Price drops
    await priceFeed.setPrice('1')

    // Liquidate B
    const txB = await positionManager.liquidate(bob)
    assert.isTrue(txB.receipt.status)
    assert.isFalse(await sortedPositions.contains(bob))

    // Check rewards for C and D
    const C_pendingRewardsAfterL2 = C_collAfterL1.mul(th.applyLiquidationFee(B_collAfterL1)).div(C_collAfterL1.add(D_coll))
    const D_pendingRewardsAfterL2 = D_coll.mul(th.applyLiquidationFee(B_collAfterL1)).div(C_collAfterL1.add(D_coll))
    const C_collAfterL2 = C_collAfterL1.add(C_pendingRewardsAfterL2)
    assert.isAtMost(th.getDifference(await positionManager.getPendingCollateralTokenReward(carol), C_pendingRewardsAfterL2), 10000000)
    assert.isAtMost(th.getDifference(await positionManager.getPendingCollateralTokenReward(dennis), D_pendingRewardsAfterL2), 10000000)

    const totalStakesSnapshotAfterL2 = totalStakesSnapshotAfterL1.add(D_coll.mul(totalStakesSnapshotAfterL1).div(totalCollateralSnapshotAfterL1)).sub(B_coll).sub(C_withdrawnColl.mul(totalStakesSnapshotAfterL1).div(totalCollateralSnapshotAfterL1))
    const defaultedAmountAfterL2 = th.applyLiquidationFee(B_coll.add(B_addedColl).add(B_pendingRewardsAfterL1)).add(C_pendingRewardsAfterL1)
    const totalCollateralSnapshotAfterL2 = C_coll.sub(C_withdrawnColl).add(D_coll).add(defaultedAmountAfterL2)
    th.assertIsApproximatelyEqual(await positionManager.totalStakesSnapshot(), totalStakesSnapshotAfterL2)
    th.assertIsApproximatelyEqual(await positionManager.totalCollateralSnapshot(), totalCollateralSnapshotAfterL2)

    // Price rises
    await priceFeed.setPrice(dec(1, 27))

    /* E and F open positions.
    E: 10000 ETH
    F: 0.0007 ETH
    */
    wstETHTokenMock.approve(positionManager.address, toBN(dec(1, 22)), { from: erin})
    const { collateral: E_coll, totalDebt: E_totalDebt } = await openPosition({ extraRAmount: dec(100, 18), amount: toBN(dec(1, 22)), extraParams: { from: erin } })
    wstETHTokenMock.approve(positionManager.address, toBN('700000000000000'), { from: erin})
    const { collateral: F_coll, totalDebt: F_totalDebt } = await openPosition({ extraRAmount: dec(100, 18), amount: toBN('700000000000000'), extraParams: { from: freddy } })

    // D tops up
    const D_addedColl = toBN(dec(1, 'ether'))
    wstETHTokenMock.approve(positionManager.address, D_addedColl, { from: dennis})
    await positionManager.addColl(dennis, dennis, D_addedColl, { from: dennis })

    const D_collAfterL2 = D_coll.add(D_pendingRewardsAfterL2).add(D_addedColl)

    // Price drops
    await priceFeed.setPrice('1')

    // Liquidate F
    const txF = await positionManager.liquidate(freddy)
    assert.isTrue(txF.receipt.status)
    assert.isFalse(await sortedPositions.contains(freddy))

    // Grab remaining positions' collateral
    const carol_rawColl = (await positionManager.positions(carol))[1].toString()
    const carol_pendingETHReward = (await positionManager.getPendingCollateralTokenReward(carol)).toString()
    const carol_Stake = (await positionManager.positions(carol))[2].toString()

    const dennis_rawColl = (await positionManager.positions(dennis))[1].toString()
    const dennis_pendingETHReward = (await positionManager.getPendingCollateralTokenReward(dennis)).toString()
    const dennis_Stake = (await positionManager.positions(dennis))[2].toString()

    const erin_rawColl = (await positionManager.positions(erin))[1].toString()
    const erin_pendingETHReward = (await positionManager.getPendingCollateralTokenReward(erin)).toString()
    const erin_Stake = (await positionManager.positions(erin))[2].toString()

    // Check raw collateral of C, D, E
    const totalCollForL3 = C_collAfterL2.add(D_collAfterL2).add(E_coll)
    const C_collAfterL3 = C_collAfterL2.add(C_collAfterL2.mul(th.applyLiquidationFee(F_coll)).div(totalCollForL3))
    const D_collAfterL3 = D_collAfterL2.add(D_collAfterL2.mul(th.applyLiquidationFee(F_coll)).div(totalCollForL3))
    const E_collAfterL3 = E_coll.add(E_coll.mul(th.applyLiquidationFee(F_coll)).div(totalCollForL3))
    assert.isAtMost(th.getDifference(carol_rawColl, C_collAfterL1), 1000)
    assert.isAtMost(th.getDifference(dennis_rawColl, D_collAfterL2), 1000000)
    assert.isAtMost(th.getDifference(erin_rawColl, E_coll), 1000)

    // Check pending ETH rewards of C, D, E
    assert.isAtMost(th.getDifference(carol_pendingETHReward, C_collAfterL3.sub(C_collAfterL1)), 1000000)
    assert.isAtMost(th.getDifference(dennis_pendingETHReward, D_collAfterL3.sub(D_collAfterL2)), 1000000)
    assert.isAtMost(th.getDifference(erin_pendingETHReward, E_collAfterL3.sub(E_coll)), 1000000)

    // Check system snapshots
    const totalStakesSnapshotAfterL3 = totalStakesSnapshotAfterL2.add(D_addedColl.add(E_coll).mul(totalStakesSnapshotAfterL2).div(totalCollateralSnapshotAfterL2))
    const totalCollateralSnapshotAfterL3 = C_coll.sub(C_withdrawnColl).add(D_coll).add(D_addedColl).add(E_coll).add(defaultedAmountAfterL2).add(th.applyLiquidationFee(F_coll))
    const totalStakesSnapshot = (await positionManager.totalStakesSnapshot()).toString()
    const totalCollateralSnapshot = (await positionManager.totalCollateralSnapshot()).toString()
    th.assertIsApproximatelyEqual(totalStakesSnapshot, totalStakesSnapshotAfterL3)
    th.assertIsApproximatelyEqual(totalCollateralSnapshot, totalCollateralSnapshotAfterL3)

    // check R gas compensation
    assert.equal((await rToken.balanceOf(owner)).toString(), dec(600, 18))
  })
})
