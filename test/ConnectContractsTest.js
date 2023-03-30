const deploymentHelper = require("../utils/deploymentHelpers.js")

contract('Deployment script - Sets correct contract addresses dependencies after deployment', async accounts => {
  const [owner] = accounts;

  let priceFeed
  let rToken
  let sortedPositions
  let positionManager
  let feeRecipient

  before(async () => {
    const coreContracts = await deploymentHelper.deployLiquityCore(owner)

    priceFeed = coreContracts.priceFeedTestnet
    rToken = coreContracts.rToken
    sortedPositions = coreContracts.sortedPositions
    positionManager = coreContracts.positionManager
    feeRecipient = owner
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

  // Fee recipient in PositionM
  it('Sets the correct fee recipient address in PositionManager', async () => {
    const recordedFeeRecipient = await positionManager.feeRecipient()
    assert.equal(feeRecipient, recordedFeeRecipient)
  })
})
