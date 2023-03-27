const deploymentHelper = require("../utils/deploymentHelpers.js")
const { TestHelper: th, MoneyValues: mv } = require("../utils/testHelpers.js")

const GasPool = artifacts.require("./GasPool.sol")
const BorrowerOperationsTester = artifacts.require("./BorrowerOperationsTester.sol")

contract('All Liquity functions with onlyOwner modifier', async accounts => {

  const [owner, alice, bob] = accounts;

  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(997, 1000)

  let contracts
  let rToken
  let sortedTroves
  let troveManager
  let activePool
  let defaultPool
  let borrowerOperations

  before(async () => {
    contracts = await deploymentHelper.deployLiquityCore()
    contracts.borrowerOperations = await BorrowerOperationsTester.new()
    contracts = await deploymentHelper.deployRToken(contracts)

    rToken = contracts.rToken
    sortedTroves = contracts.sortedTroves
    troveManager = contracts.troveManager
    activePool = contracts.activePool
    defaultPool = contracts.defaultPool
    borrowerOperations = contracts.borrowerOperations
  })

  const testZeroAddress = async (contract, params, skipLast = 0) => {
    await testWrongAddress(contract, params, th.ZERO_ADDRESS, skipLast, 'Account cannot be zero address')
  }
  const testNonContractAddress = async (contract, params, skipLast = 0) => {
    await testWrongAddress(contract, params, bob, skipLast, 'Account code size cannot be zero')
  }
  const testWrongAddress = async (contract, params, address, skipLast, message) => {
    for (let i = 0; i < params.length - skipLast; i++) {
      const newParams = [...params]
      newParams[i] = address
      await th.assertRevert(contract.setAddresses(...newParams, { from: owner }), message)
    }
  }

  const testSetAddresses = async (contract, numberOfAddresses, skipLast = 0) => {
    const dumbContract = await GasPool.new()
    const params = [...Array(numberOfAddresses).fill(dumbContract.address)]

    // Attempt call from alice
    await th.assertRevert(contract.setAddresses(...params, { from: alice }))

    // Owner can successfully set any address
    const txOwner = await contract.setAddresses(...params, { from: owner })
    assert.isTrue(txOwner.receipt.status)
    // fails if called twice
    await th.assertRevert(contract.setAddresses(...params, { from: owner }))
  }

  describe('TroveManager', async accounts => {
    it("setAddresses(): reverts when called by non-owner, with wrong addresses, or twice", async () => {
      await testSetAddresses(troveManager, 9, 1)
    })

    it("setBorrowingSpread(): reverts when called by non-owner, or with wrong values", async () => {
      // Attempt call from alice
      await th.assertRevert(troveManager.setBorrowingSpread(100, { from: alice }))

      // Attempt to set spread above max
      await th.assertRevert(troveManager.setBorrowingSpread(th.toBN(th.dec(10, 18)), { from: owner }))

      // Owner can successfully set spread
      const txOwner = await troveManager.setBorrowingSpread(100, { from: owner })
      assert.isTrue(txOwner.receipt.status)
    })
  })

  describe('BorrowerOperations', async accounts => {
    it("setAddresses(): reverts when called by non-owner, with wrong addresses, or twice", async () => {
      await testSetAddresses(borrowerOperations, 9, 1)
    })
  })

  describe('ActivePool', async accounts => {
    it("setAddresses(): reverts when called by non-owner, with wrong addresses, or twice", async () => {
      await testSetAddresses(activePool, 3)
    })
  })

  describe('SortedTroves', async accounts => {
    it("setParams(): reverts when called by non-owner, with wrong addresses, or twice", async () => {
      const dumbContract = await GasPool.new()
      const params = [10000001, dumbContract.address, dumbContract.address]

      // Attempt call from alice
      await th.assertRevert(sortedTroves.setParams(...params, { from: alice }))

      // Attempt to use zero address
      await testZeroAddress(sortedTroves, params, 'setParams', 1)
      // Attempt to use non contract
      await testNonContractAddress(sortedTroves, params, 'setParams', 1)

      // Owner can successfully set params
      const txOwner = await sortedTroves.setParams(...params, { from: owner })
      assert.isTrue(txOwner.receipt.status)

      // fails if called twice
      await th.assertRevert(sortedTroves.setParams(...params, { from: owner }))
    })
  })
})

