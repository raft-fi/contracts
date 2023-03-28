
const SortedPositions = artifacts.require("./SortedPositions.sol")
const PositionManager = artifacts.require("./PositionManager.sol")
const PriceFeedTestnet = artifacts.require("./PriceFeedTestnet.sol")
const RToken = artifacts.require("./RToken.sol")
const ActivePool = artifacts.require("./ActivePool.sol");
const DefaultPool = artifacts.require("./DefaultPool.sol");
const StabilityPool = artifacts.require("./StabilityPool.sol")
const FunctionCaller = artifacts.require("./FunctionCaller.sol")

const deployLiquity = async () => {
  const priceFeedTestnet = await PriceFeedTestnet.new()
  const sortedPositions = await SortedPositions.new()
  const positionManager = await PositionManager.new()
  const activePool = await ActivePool.new()
  const stabilityPool = await StabilityPool.new()
  const defaultPool = await DefaultPool.new()
  const functionCaller = await FunctionCaller.new()
  const rToken = await RToken.new(
    positionManager.address,
    stabilityPool.address
  )
  DefaultPool.setAsDeployed(defaultPool)
  PriceFeedTestnet.setAsDeployed(priceFeedTestnet)
  RToken.setAsDeployed(rToken)
  SortedPositions.setAsDeployed(sortedPositions)
  PositionManager.setAsDeployed(positionManager)
  ActivePool.setAsDeployed(activePool)
  StabilityPool.setAsDeployed(stabilityPool)
  FunctionCaller.setAsDeployed(functionCaller)

  const contracts = {
    priceFeedTestnet,
    rToken,
    sortedPositions,
    positionManager,
    activePool,
    stabilityPool,
    defaultPool,
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
    StabilityPool: contracts.stabilityPool.address,
    ActivePool: contracts.activePool.address,
    DefaultPool: contracts.defaultPool.address,
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
  await contracts.positionManager.setActivePool(addresses.ActivePool)
  await contracts.positionManager.setDefaultPool(addresses.DefaultPool)
  await contracts.positionManager.setStabilityPool(addresses.StabilityPool)

  // set contracts in the Pools
  await contracts.stabilityPool.setActivePoolAddress(addresses.ActivePool)
  await contracts.stabilityPool.setDefaultPoolAddress(addresses.DefaultPool)

  await contracts.activePool.setStabilityPoolAddress(addresses.StabilityPool)
  await contracts.activePool.setDefaultPoolAddress(addresses.DefaultPool)

  await contracts.defaultPool.setStabilityPoolAddress(addresses.StabilityPool)
  await contracts.defaultPool.setActivePoolAddress(addresses.ActivePool)
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
