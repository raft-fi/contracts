const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")

const SortedPositions = artifacts.require("SortedPositions")
const SortedPositionsTester = artifacts.require("SortedPositionsTester")
const PositionManagerTester = artifacts.require("PositionManagerTester")
const RToken = artifacts.require("RToken")

const th = testHelpers.TestHelper
const dec = th.dec
const toBN = th.toBN
const mv = testHelpers.MoneyValues

contract('SortedPositions', async accounts => {

  const assertSortedListIsOrdered = async (contracts) => {
    const price = await contracts.priceFeedTestnet.getPrice()

    let position = await contracts.sortedPositions.getLast()
    while (position !== (await contracts.sortedPositions.getFirst())) {

      // Get the adjacent upper position ("prev" moves up the list, from lower ICR -> higher ICR)
      const prevPosition = await contracts.sortedPositions.getPrev(position)

      const positionICR = await contracts.positionManager.getCurrentICR(position, price)
      const prevPositionICR = await contracts.positionManager.getCurrentICR(prevPosition, price)

      assert.isTrue(prevPositionICR.gte(positionICR))

      const positionNICR = await contracts.positionManager.getNominalICR(position)
      const prevPositionNICR = await contracts.positionManager.getNominalICR(prevPosition)

      assert.isTrue(prevPositionNICR.gte(positionNICR))

      // climb the list
      position = prevPosition
    }
  }

  const [
    owner, alice, bob, carol, dennis, erin,
    defaulter_1,
    A, B, C, D, E, F, G, H, I, J, whale] = accounts;

  let priceFeed
  let sortedPositions
  let positionManager
  let rToken

  let contracts

  const openPosition = async (params) => th.openPosition(contracts, params)

  describe('SortedPositions', () => {
    beforeEach(async () => {
      contracts = await deploymentHelper.deployLiquityCore()
      contracts.positionManager = await PositionManagerTester.new()
      contracts.rToken = await RToken.new(
        contracts.positionManager.address
      )

      priceFeed = contracts.priceFeedTestnet
      sortedPositions = contracts.sortedPositions
      positionManager = contracts.positionManager
      rToken = contracts.rToken

      await deploymentHelper.connectCoreContracts(contracts, owner)

      await th.fillAccountsWithWstETH(contracts, [
        alice, bob, carol, dennis, erin,
        defaulter_1,
        A, B, C, D, E, F, G, H, I, J, whale
      ])
    })

    it('contains(): returns true for addresses that have opened positions', async () => {
      await openPosition({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
      await openPosition({ ICR: toBN(dec(20, 18)), extraParams: { from: bob } })
      await openPosition({ ICR: toBN(dec(2000, 18)), extraParams: { from: carol } })

      // Confirm position statuses became active
      assert.equal((await positionManager.positions(alice))[3], '1')
      assert.equal((await positionManager.positions(bob))[3], '1')
      assert.equal((await positionManager.positions(carol))[3], '1')

      // Check sorted list contains positions
      assert.isTrue(await sortedPositions.contains(alice))
      assert.isTrue(await sortedPositions.contains(bob))
      assert.isTrue(await sortedPositions.contains(carol))
    })

    it('contains(): returns false for addresses that have not opened positions', async () => {
      await openPosition({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
      await openPosition({ ICR: toBN(dec(20, 18)), extraParams: { from: bob } })
      await openPosition({ ICR: toBN(dec(2000, 18)), extraParams: { from: carol } })

      // Confirm positions have non-existent status
      assert.equal((await positionManager.positions(dennis))[3], '0')
      assert.equal((await positionManager.positions(erin))[3], '0')

      // Check sorted list do not contain positions
      assert.isFalse(await sortedPositions.contains(dennis))
      assert.isFalse(await sortedPositions.contains(erin))
    })

    it('contains(): returns false for addresses that opened and then closed a position', async () => {
      await openPosition({ ICR: toBN(dec(1000, 18)), extraRAmount: toBN(dec(3000, 18)), extraParams: { from: whale } })

      await openPosition({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
      await openPosition({ ICR: toBN(dec(20, 18)), extraParams: { from: bob } })
      await openPosition({ ICR: toBN(dec(2000, 18)), extraParams: { from: carol } })

      // to compensate borrowing fees
      await rToken.transfer(alice, dec(1000, 18), { from: whale })
      await rToken.transfer(bob, dec(1000, 18), { from: whale })
      await rToken.transfer(carol, dec(1000, 18), { from: whale })

      // A, B, C close positions
      await positionManager.closePosition({ from: alice })
      await positionManager.closePosition({ from:bob })
      await positionManager.closePosition({ from:carol })

      // Confirm position statuses became closed
      assert.equal((await positionManager.positions(alice))[3], '2')
      assert.equal((await positionManager.positions(bob))[3], '2')
      assert.equal((await positionManager.positions(carol))[3], '2')

      // Check sorted list does not contain positions
      assert.isFalse(await sortedPositions.contains(alice))
      assert.isFalse(await sortedPositions.contains(bob))
      assert.isFalse(await sortedPositions.contains(carol))
    })

    // true for addresses that opened -> closed -> opened a position
    it('contains(): returns true for addresses that opened, closed and then re-opened a position', async () => {
      await openPosition({ ICR: toBN(dec(1000, 18)), extraRAmount: toBN(dec(3000, 18)), extraParams: { from: whale } })

      await openPosition({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })
      await openPosition({ ICR: toBN(dec(20, 18)), extraParams: { from: bob } })
      await openPosition({ ICR: toBN(dec(2000, 18)), extraParams: { from: carol } })

      // to compensate borrowing fees
      await rToken.transfer(alice, dec(1000, 18), { from: whale })
      await rToken.transfer(bob, dec(1000, 18), { from: whale })
      await rToken.transfer(carol, dec(1000, 18), { from: whale })

      // A, B, C close positions
      await positionManager.closePosition({ from: alice })
      await positionManager.closePosition({ from:bob })
      await positionManager.closePosition({ from:carol })

      // Confirm position statuses became closed
      assert.equal((await positionManager.positions(alice))[3], '2')
      assert.equal((await positionManager.positions(bob))[3], '2')
      assert.equal((await positionManager.positions(carol))[3], '2')

      await openPosition({ ICR: toBN(dec(1000, 16)), extraParams: { from: alice } })
      await openPosition({ ICR: toBN(dec(2000, 18)), extraParams: { from: bob } })
      await openPosition({ ICR: toBN(dec(3000, 18)), extraParams: { from: carol } })

      // Confirm position statuses became open again
      assert.equal((await positionManager.positions(alice))[3], '1')
      assert.equal((await positionManager.positions(bob))[3], '1')
      assert.equal((await positionManager.positions(carol))[3], '1')

      // Check sorted list does  contain positions
      assert.isTrue(await sortedPositions.contains(alice))
      assert.isTrue(await sortedPositions.contains(bob))
      assert.isTrue(await sortedPositions.contains(carol))
    })

    // false when list size is 0
    it('contains(): returns false when there are no positions in the system', async () => {
      assert.isFalse(await sortedPositions.contains(alice))
      assert.isFalse(await sortedPositions.contains(bob))
      assert.isFalse(await sortedPositions.contains(carol))
    })

    // true when list size is 1 and the position the only one in system
    it('contains(): true when list size is 1 and the position the only one in system', async () => {
      await openPosition({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })

      assert.isTrue(await sortedPositions.contains(alice))
    })

    // false when list size is 1 and position is not in the system
    it('contains(): false when list size is 1 and position is not in the system', async () => {
      await openPosition({ ICR: toBN(dec(150, 16)), extraParams: { from: alice } })

      assert.isFalse(await sortedPositions.contains(bob))
    })

    // --- getMaxSize ---

    it("getMaxSize(): Returns the maximum list size", async () => {
      const max = await sortedPositions.getMaxSize()
      assert.equal(web3.utils.toHex(max), th.maxBytes32)
    })

    // --- findInsertPosition ---

    it("Finds the correct insert position given two addresses that loosely bound the correct position", async () => {
      await priceFeed.setPrice(dec(100, 18))

      // NICR sorted in descending order
      await openPosition({ ICR: toBN(dec(500, 18)), extraParams: { from: whale } })
      await openPosition({ ICR: toBN(dec(10, 18)), extraParams: { from: A } })
      await openPosition({ ICR: toBN(dec(5, 18)), extraParams: { from: B } })
      await openPosition({ ICR: toBN(dec(250, 16)), extraParams: { from: C } })
      await openPosition({ ICR: toBN(dec(166, 16)), extraParams: { from: D } })
      await openPosition({ ICR: toBN(dec(125, 16)), extraParams: { from: E } })

      // Expect a position with NICR 300% to be inserted between B and C
      const targetNICR = dec(3, 18)

      // Pass addresses that loosely bound the right postiion
      const hints = await sortedPositions.findInsertPosition(targetNICR, A, E)

      // Expect the exact correct insert hints have been returned
      assert.equal(hints[0], B )
      assert.equal(hints[1], C )

      // The price doesn’t affect the hints
      await priceFeed.setPrice(dec(500, 18))
      const hints2 = await sortedPositions.findInsertPosition(targetNICR, A, E)

      // Expect the exact correct insert hints have been returned
      assert.equal(hints2[0], B )
      assert.equal(hints2[1], C )
    })

    //--- Ordering ---
    // infinte ICR (zero collateral) is not possible anymore, therefore, skipping
    it.skip("stays ordered after positions with 'infinite' ICR receive a redistribution", async () => {

      // make several positions with 0 debt and collateral, in random order
      await positionManager.openPosition(th._100pct, 0, whale, whale, { from: whale, value: dec(50, 'ether') })
      await positionManager.openPosition(th._100pct, 0, A, A, { from: A, value: dec(1, 'ether') })
      await positionManager.openPosition(th._100pct, 0, B, B, { from: B, value: dec(37, 'ether') })
      await positionManager.openPosition(th._100pct, 0, C, C, { from: C, value: dec(5, 'ether') })
      await positionManager.openPosition(th._100pct, 0, D, D, { from: D, value: dec(4, 'ether') })
      await positionManager.openPosition(th._100pct, 0, E, E, { from: E, value: dec(19, 'ether') })

      // Make some positions with non-zero debt, in random order
      await positionManager.openPosition(th._100pct, dec(5, 19), F, F, { from: F, value: dec(1, 'ether') })
      await positionManager.openPosition(th._100pct, dec(3, 18), G, G, { from: G, value: dec(37, 'ether') })
      await positionManager.openPosition(th._100pct, dec(2, 20), H, H, { from: H, value: dec(5, 'ether') })
      await positionManager.openPosition(th._100pct, dec(17, 18), I, I, { from: I, value: dec(4, 'ether') })
      await positionManager.openPosition(th._100pct, dec(5, 21), J, J, { from: J, value: dec(1345, 'ether') })

      // Check positions are ordered
      await assertSortedListIsOrdered(contracts)

      await positionManager.openPosition(th._100pct, dec(100, 18), defaulter_1, defaulter_1, { from: defaulter_1, value: dec(1, 'ether') })
      assert.isTrue(await sortedPositions.contains(defaulter_1))

      // Price drops
      await priceFeed.setPrice(dec(100, 18))

      // Liquidate a position
      await positionManager.liquidate(defaulter_1)
      assert.isFalse(await sortedPositions.contains(defaulter_1))

      // Check positions are ordered
      await assertSortedListIsOrdered(contracts)
    })
  })

  describe('SortedPositions with mock dependencies', () => {
    let sortedPositionsTester

    beforeEach(async () => {
      sortedPositions = await SortedPositions.new()
      sortedPositionsTester = await SortedPositionsTester.new()

      await sortedPositionsTester.setSortedPositions(sortedPositions.address)
    })

    context('when params are wrongly set', () => {
      it('setParams(): reverts if size is zero', async () => {
        await th.assertRevert(sortedPositions.setParams(0, sortedPositionsTester.address), 'SortedPositions: Size cannot be zero')
      })
    })

    context('when params are properly set', () => {
      beforeEach('set params', async() => {
        await sortedPositions.setParams(2, sortedPositionsTester.address)
      })

      it('insert(): fails if list is full', async () => {
        await sortedPositionsTester.insert(alice, 1, alice, alice)
        await sortedPositionsTester.insert(bob, 1, alice, alice)
        await th.assertRevert(sortedPositionsTester.insert(carol, 1, alice, alice), 'SortedPositions: List is full')
      })

      it('insert(): fails if list already contains the node', async () => {
        await sortedPositionsTester.insert(alice, 1, alice, alice)
        await th.assertRevert(sortedPositionsTester.insert(alice, 1, alice, alice), 'SortedPositions: List already contains the node')
      })

      it('insert(): fails if id is zero', async () => {
        await th.assertRevert(sortedPositionsTester.insert(th.ZERO_ADDRESS, 1, alice, alice), 'SortedPositions: Id cannot be zero')
      })

      it('insert(): fails if NICR is zero', async () => {
        await th.assertRevert(sortedPositionsTester.insert(alice, 0, alice, alice), 'SortedPositions: NICR must be positive')
      })

      it('remove(): fails if id is not in the list', async () => {
        await th.assertRevert(sortedPositionsTester.remove(alice), 'SortedPositions: List does not contain the id')
      })

      it('reInsert(): fails if list doesn’t contain the node', async () => {
        await th.assertRevert(sortedPositionsTester.reInsert(alice, 1, alice, alice), 'SortedPositions: List does not contain the id')
      })

      it('reInsert(): fails if new NICR is zero', async () => {
        await sortedPositionsTester.insert(alice, 1, alice, alice)
        assert.isTrue(await sortedPositions.contains(alice), 'list should contain element')
        await th.assertRevert(sortedPositionsTester.reInsert(alice, 0, alice, alice), 'SortedPositions: NICR must be positive')
        assert.isTrue(await sortedPositions.contains(alice), 'list should contain element')
      })

      it('findInsertPosition(): No prevId for hint - ascend list starting from nextId, result is after the tail', async () => {
        await sortedPositionsTester.insert(alice, 1, alice, alice)
        const pos = await sortedPositions.findInsertPosition(1, th.ZERO_ADDRESS, alice)
        assert.equal(pos[0], alice, 'prevId result should be nextId param')
        assert.equal(pos[1], th.ZERO_ADDRESS, 'nextId result should be zero')
      })
    })
  })
})
