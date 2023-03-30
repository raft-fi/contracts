const PositionManager = artifacts.require("./PositionManager.sol")
const PriceFeedTestnet = artifacts.require("./PriceFeedTestnet.sol")
const RToken = artifacts.require("./RToken.sol")

const deployLiquity = async () => {
  const priceFeedTestnet = await PriceFeedTestnet.new()
  const positionManager = await PositionManager.new()
  const rToken = await RToken.new(positionManager.address)
  PriceFeedTestnet.setAsDeployed(priceFeedTestnet)
  RToken.setAsDeployed(rToken)
  PositionManager.setAsDeployed(positionManager)

  const contracts = {
    priceFeedTestnet,
    rToken,
    positionManager
  }
  return contracts
}

const getAddresses = (contracts) => {
  return {
    PriceFeedTestnet: contracts.priceFeedTestnet.address,
    RToken: contracts.rToken.address,
    PositionManager: contracts.positionManager.address
  }
}

// Connect contracts to their dependencies
const connectContracts = async (contracts, addresses) => {
  // set PositionManager addr in PriceFeed
  await contracts.priceFeedTestnet.setPositionManagerAddress(addresses.PositionManager)

  // set contracts in the Position Manager
  await contracts.positionManager.setRToken(addresses.RToken)
  await contracts.positionManager.setPriceFeed(addresses.PriceFeedTestnet)
}

const connectEchidnaProxy = async (echidnaProxy, addresses) => {
  echidnaProxy.setPositionManager(addresses.PositionManager)
}

module.exports = {
  connectEchidnaProxy: connectEchidnaProxy,
  getAddresses: getAddresses,
  deployLiquity: deployLiquity,
  connectContracts: connectContracts
}
