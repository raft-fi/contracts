const deploymentHelper = require("../utils/deploymentHelpers.js")

contract('Deployment script - Sets correct contract addresses dependencies after deployment', async accounts => {
  const [owner] = accounts;

  let priceFeed
  let rToken
  let sortedPositions
  let positionManager
  let activePool
  let defaultPool
  let feeRecipient

  before(async () => {
    const coreContracts = await deploymentHelper.deployLiquityCore()

    priceFeed = coreContracts.priceFeedTestnet
    rToken = coreContracts.rToken
    sortedPositions = coreContracts.sortedPositions
    positionManager = coreContracts.positionManager
    activePool = coreContracts.activePool
    defaultPool = coreContracts.defaultPool
    functionCaller = coreContracts.functionCaller
    feeRecipient = owner

    await deploymentHelper.connectCoreContracts(coreContracts, feeRecipient)
  })

  it('Sets the correct PriceFeed address in PositionManager', async () => {
    const priceFeedAddress = priceFeed.address

    const recordedPriceFeedAddress = await positionManager.priceFeed()

    assert.equal(priceFeedAddress, recordedPriceFeedAddress)
  })

  it('Sets the correct RToken address in PositionManager', async () => {
    const rTokenAddress = rToken.address

    const recordedClvTokenAddress = await positionManager.rToken()

    assert.equal(rTokenAddress, recordedClvTokenAddress)
  })

  it('Sets the correct SortedPositions address in PositionManager', async () => {
    const sortedPositionsAddress = sortedPositions.address

    const recordedSortedPositionsAddress = await positionManager.sortedPositions()

    assert.equal(sortedPositionsAddress, recordedSortedPositionsAddress)
  })

  // ActivePool in PositionM
  it('Sets the correct ActivePool address in PositionManager', async () => {
    const activePoolAddress = activePool.address

    const recordedActivePoolAddresss = await positionManager.activePool()

    assert.equal(activePoolAddress, recordedActivePoolAddresss)
  })

  // DefaultPool in PositionM
  it('Sets the correct DefaultPool address in PositionManager', async () => {
    const defaultPoolAddress = defaultPool.address

    const recordedDefaultPoolAddresss = await positionManager.defaultPool()

    assert.equal(defaultPoolAddress, recordedDefaultPoolAddresss)
  })

  // Fee recipient in PositionM
  it('Sets the correct fee recipient address in PositionManager', async () => {
    const recordedFeeRecipient = await positionManager.feeRecipient()
    assert.equal(feeRecipient, recordedFeeRecipient)
  })

  // Active Pool

  it('Sets the correct DefaultPool address in ActivePool', async () => {
    const defaultPoolAddress = defaultPool.address

    const recordedDefaultPoolAddress = await activePool.defaultPool()

    assert.equal(defaultPoolAddress, recordedDefaultPoolAddress)
  })

  it('Sets the correct PositionManager address in ActivePool', async () => {
    const positionManagerAddress = positionManager.address

    const recordedPositionManagerAddress = await activePool.positionManager()
    assert.equal(positionManagerAddress, recordedPositionManagerAddress)
  })

  // Default Pool

  it('Sets the correct PositionManager address in DefaultPool', async () => {
    const positionManagerAddress = positionManager.address

    const recordedPositionManagerAddress = await defaultPool.positionManager()
    assert.equal(positionManagerAddress, recordedPositionManagerAddress)
  })

  it('Sets the correct PositionManager address in SortedPositions', async () => {
    const positionManagerAddress = positionManager.address

    const recordedPositionManagerAddress = await sortedPositions.positionManager()
    assert.equal(positionManagerAddress, recordedPositionManagerAddress)
  })
})
