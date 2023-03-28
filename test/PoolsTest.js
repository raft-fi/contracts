const ActivePool = artifacts.require("./ActivePool.sol")
const DefaultPool = artifacts.require("./DefaultPool.sol")
const NonPayable = artifacts.require("./NonPayable.sol")
const WstETHTokenMock = artifacts.require("./WstETHTokenMock.sol")

const testHelpers = require("../utils/testHelpers.js")

const th = testHelpers.TestHelper
const dec = th.dec

const _minus_1_Ether = web3.utils.toWei('-1', 'ether')

contract('ActivePool', async accounts => {

  let activePool, mockBorrowerOperations, wstETHTokenMock

  const [owner, alice] = accounts;
  beforeEach(async () => {
    wstETHTokenMock = await WstETHTokenMock.new()
    activePool = await ActivePool.new(wstETHTokenMock.address)
    mockBorrowerOperations = await NonPayable.new()
    const dumbContractAddress = (await NonPayable.new()).address
    await activePool.setAddresses(mockBorrowerOperations.address, dumbContractAddress, dumbContractAddress)

    await th.fillAccountsWithWstETH({wstETHTokenMock: wstETHTokenMock}, [owner, alice])
  })

  it('CollateralBalance(): gets the recorded collateralToken balance', async () => {
    const recordedETHBalance = await activePool.collateralBalance()
    assert.equal(recordedETHBalance, 0)
  })

  it('getRDebt(): gets the recorded R balance', async () => {
    const recordedETHBalance = await activePool.getRDebt()
    assert.equal(recordedETHBalance, 0)
  })

  it('increaseR(): increases the recorded R balance by the correct amount', async () => {
    const recordedR_balanceBefore = await activePool.getRDebt()
    assert.equal(recordedR_balanceBefore, 0)

    // await activePool.increaseRDebt(100, { from: mockBorrowerOperationsAddress })
    const increaseRDebtData = th.getTransactionData('increaseRDebt(uint256)', ['0x64'])
    const tx = await mockBorrowerOperations.forward(activePool.address, increaseRDebtData)
    assert.isTrue(tx.receipt.status)
    const recordedR_balanceAfter = await activePool.getRDebt()
    assert.equal(recordedR_balanceAfter, 100)
  })
  // Decrease
  it('decreaseR(): decreases the recorded R balance by the correct amount', async () => {
    // start the pool on 100 wei
    //await activePool.increaseRDebt(100, { from: mockBorrowerOperationsAddress })
    const increaseRDebtData = th.getTransactionData('increaseRDebt(uint256)', ['0x64'])
    const tx1 = await mockBorrowerOperations.forward(activePool.address, increaseRDebtData)
    assert.isTrue(tx1.receipt.status)

    const recordedR_balanceBefore = await activePool.getRDebt()
    assert.equal(recordedR_balanceBefore, 100)

    //await activePool.decreaseRDebt(100, { from: mockBorrowerOperationsAddress })
    const decreaseRDebtData = th.getTransactionData('decreaseRDebt(uint256)', ['0x64'])
    const tx2 = await mockBorrowerOperations.forward(activePool.address, decreaseRDebtData)
    assert.isTrue(tx2.receipt.status)
    const recordedR_balanceAfter = await activePool.getRDebt()
    assert.equal(recordedR_balanceAfter, 0)
  })

  // send raw ether
  it('withdrawCollateral(): decreases the recorded ETH balance by the correct amount', async () => {
    // setup: give pool 2 ether
    const activePool_initialBalance = web3.utils.toBN(await web3.eth.getBalance(activePool.address))
    assert.equal(activePool_initialBalance, 0)
    // start pool with 2 ether
    await wstETHTokenMock.approve(activePool.address, dec(2, 'ether'), { from: owner})
    const depositWstETHData = th.getTransactionData('depositCollateral(address,uint256)', [owner, dec(2, 'ether')])
    await mockBorrowerOperations.forward(activePool.address, depositWstETHData, { from: owner })
    const activePool_BalanceBeforeTx = web3.utils.toBN(await wstETHTokenMock.balanceOf(activePool.address))
    const alice_Balance_BeforeTx = web3.utils.toBN(await wstETHTokenMock.balanceOf(alice))

    assert.equal(activePool_BalanceBeforeTx, dec(2, 'ether'))

    // send ether from pool to alice
    const sendETHData = th.getTransactionData('withdrawCollateral(address,uint256)', [alice, web3.utils.toHex(dec(1, 'ether'))])
    const tx2 = await mockBorrowerOperations.forward(activePool.address, sendETHData, { from: owner })
    assert.isTrue(tx2.receipt.status)

    const activePool_BalanceAfterTx = web3.utils.toBN(await wstETHTokenMock.balanceOf(activePool.address))
    const alice_Balance_AfterTx = web3.utils.toBN(await wstETHTokenMock.balanceOf(alice))

    const alice_BalanceChange = alice_Balance_AfterTx.sub(alice_Balance_BeforeTx)
    const pool_BalanceChange = activePool_BalanceAfterTx.sub(activePool_BalanceBeforeTx)
    assert.equal(alice_BalanceChange, dec(1, 'ether'))
    assert.equal(pool_BalanceChange, _minus_1_Ether)
  })
})

contract('DefaultPool', async accounts => {

  let wstETHTokenMock, defaultPool, mockTroveManager

  const [owner, alice] = accounts;
  beforeEach(async () => {
    wstETHTokenMock = await WstETHTokenMock.new()
    defaultPool = await DefaultPool.new(wstETHTokenMock.address)
    mockTroveManager = await NonPayable.new()
    await defaultPool.setAddresses(mockTroveManager.address)

    await th.fillAccountsWithWstETH({wstETHTokenMock: wstETHTokenMock}, [owner, alice])
  })

  it('collateralBalance(): gets the recorded collateralToken balance', async () => {
    const recordedETHBalance = await defaultPool.collateralBalance()
    assert.equal(recordedETHBalance, 0)
  })

  it('getRDebt(): gets the recorded R balance', async () => {
    const recordedETHBalance = await defaultPool.getRDebt()
    assert.equal(recordedETHBalance, 0)
  })

  it('increaseR(): increases the recorded R balance by the correct amount', async () => {
    const recordedR_balanceBefore = await defaultPool.getRDebt()
    assert.equal(recordedR_balanceBefore, 0)

    // await defaultPool.increaseRDebt(100, { from: mockTroveManagerAddress })
    const increaseRDebtData = th.getTransactionData('increaseRDebt(uint256)', ['0x64'])
    const tx = await mockTroveManager.forward(defaultPool.address, increaseRDebtData)
    assert.isTrue(tx.receipt.status)

    const recordedR_balanceAfter = await defaultPool.getRDebt()
    assert.equal(recordedR_balanceAfter, 100)
  })

  it('decreaseR(): decreases the recorded R balance by the correct amount', async () => {
    // start the pool on 100 wei
    //await defaultPool.increaseRDebt(100, { from: mockTroveManagerAddress })
    const increaseRDebtData = th.getTransactionData('increaseRDebt(uint256)', ['0x64'])
    const tx1 = await mockTroveManager.forward(defaultPool.address, increaseRDebtData)
    assert.isTrue(tx1.receipt.status)

    const recordedR_balanceBefore = await defaultPool.getRDebt()
    assert.equal(recordedR_balanceBefore, 100)

    // await defaultPool.decreaseRDebt(100, { from: mockTroveManagerAddress })
    const decreaseRDebtData = th.getTransactionData('decreaseRDebt(uint256)', ['0x64'])
    const tx2 = await mockTroveManager.forward(defaultPool.address, decreaseRDebtData)
    assert.isTrue(tx2.receipt.status)

    const recordedR_balanceAfter = await defaultPool.getRDebt()
    assert.equal(recordedR_balanceAfter, 0)
  })
})

contract('Reset chain state', async accounts => {})
