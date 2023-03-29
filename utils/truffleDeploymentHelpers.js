
const SortedPositions = artifacts.require("./SortedPositions.sol")
const PositionManager = artifacts.require("./PositionManager.sol")
const PriceFeedTestnet = artifacts.require("./PriceFeedTestnet.sol")
const RToken = artifacts.require("./RToken.sol")
const FunctionCaller = artifacts.require("./FunctionCaller.sol")

const deployLiquity = async () => {
  const priceFeedTestnet = await PriceFeedTestnet.new()
  const sortedPositions = await SortedPositions.new()
  const positionManager = await PositionManager.new()
  const functionCaller = await FunctionCaller.new()
  const rToken = await RToken.new(positionManager.address)
  PriceFeedTestnet.setAsDeployed(priceFeedTestnet)
  RToken.setAsDeployed(rToken)
  SortedPositions.setAsDeployed(sortedPositions)
  PositionManager.setAsDeployed(positionManager)
  FunctionCaller.setAsDeployed(functionCaller)

  const contracts = {
    priceFeedTestnet,
    rToken,
    sortedPositions,
    positionManager,
    functionCaller
  }
  return contracts
}

const getAddresses = (contracts) => {
  return {
    PriceFeedTestnet: contracts.priceFeedTestnet.address,
    RToken: contracts.rToken.address,
    SortedPositions: contracts.sortedPositions.address,
    PositionManager: contracts.positionManager.address,
    FunctionCaller: contracts.functionCaller.address
  }
}

// Connect contracts to their dependencies
const connectContracts = async (contracts, addresses) => {
  // set PositionManager addr in SortedPositions
  await contracts.sortedPositions.setPositionManager(addresses.PositionManager)

  // set contract addresses in the FunctionCaller
  await contracts.functionCaller.setPositionManagerAddress(addresses.PositionManager)
  await contracts.functionCaller.setSortedPositionsAddress(addresses.SortedPositions)

  // set PositionManager addr in PriceFeed
  await contracts.priceFeedTestnet.setPositionManagerAddress(addresses.PositionManager)

  // set contracts in the Position Manager
  await contracts.positionManager.setRToken(addresses.RToken)
  await contracts.positionManager.setSortedPositions(addresses.SortedPositions)
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
