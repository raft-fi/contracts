const SortedPositions = artifacts.require("./SortedPositions.sol")
const PositionManager = artifacts.require("./PositionManager.sol")
const PriceFeedTestnet = artifacts.require("./PriceFeedTestnet.sol")
const RToken = artifacts.require("./RToken.sol")
const ActivePool = artifacts.require("./ActivePool.sol");
const DefaultPool = artifacts.require("./DefaultPool.sol");
const FunctionCaller = artifacts.require("./TestContracts/FunctionCaller.sol")
const HintHelpers = artifacts.require("./HintHelpers.sol")

const ActivePoolTester = artifacts.require("./ActivePoolTester.sol")
const DefaultPoolTester = artifacts.require("./DefaultPoolTester.sol")
const LiquityMathTester = artifacts.require("./LiquityMathTester.sol")
const PositionManagerTester = artifacts.require("./PositionManagerTester.sol")
const RTokenTester = artifacts.require("./RTokenTester.sol")
const WstETHTokenMock = artifacts.require("./WstETHTokenMock.sol")

const th = require("./testHelpers.js").TestHelper

/* "Liquity core" consists of all contracts in the core Liquity system.

*/
const maxBytes32 = '0x' + 'f'.repeat(64)

class DeploymentHelper {

  static async deployLiquityCore() {
    const cmdLineArgs = process.argv
    const frameworkPath = cmdLineArgs[1]
    // console.log(`Framework used:  ${frameworkPath}`)

    if (frameworkPath.includes("hardhat")) {
      return this.deployLiquityCoreHardhat()
    } else if (frameworkPath.includes("truffle")) {
      return this.deployLiquityCoreTruffle()
    }
  }

  static async deployLiquityCoreHardhat() {
    const priceFeedTestnet = await PriceFeedTestnet.new()
    const sortedPositions = await SortedPositions.new()
    const positionManager = await PositionManager.new()
    const wstETHTokenMock = await WstETHTokenMock.new()
    const activePool = await ActivePool.new(wstETHTokenMock.address)
    const defaultPool = await DefaultPool.new(wstETHTokenMock.address)
    const functionCaller = await FunctionCaller.new()
    const hintHelpers = await HintHelpers.new()
    const rToken = await RToken.new(
      positionManager.address
    )
    RToken.setAsDeployed(rToken)
    DefaultPool.setAsDeployed(defaultPool)
    PriceFeedTestnet.setAsDeployed(priceFeedTestnet)
    SortedPositions.setAsDeployed(sortedPositions)
    PositionManager.setAsDeployed(positionManager)
    ActivePool.setAsDeployed(activePool)
    FunctionCaller.setAsDeployed(functionCaller)
    HintHelpers.setAsDeployed(hintHelpers)

    const coreContracts = {
      priceFeedTestnet,
      rToken,
      sortedPositions,
      positionManager,
      wstETHTokenMock,
      activePool,
      defaultPool,
      functionCaller,
      hintHelpers
    }
    return coreContracts
  }

  static async mintR(rToken, to = null, amount = null) {
    to = to || (await ethers.getSigners())[0].address;
    amount = amount ? ethers.BigNumber.from(amount) : ethers.BigNumber.from("1000000000000000000000000")

    const positionManagerAddress = await rToken.positionManager();
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [positionManagerAddress]
    })
    await rToken.mint(to, amount, { from: positionManagerAddress, gasPrice: 0 })

    await hre.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [positionManagerAddress]
    })
  }

  static async deployTesterContractsHardhat() {
    const testerContracts = {}

    // Contract without testers (yet)
    testerContracts.priceFeedTestnet = await PriceFeedTestnet.new()
    testerContracts.sortedPositions = await SortedPositions.new()
    testerContracts.wstETHTokenMock = await WstETHTokenMock.new();
    // Actual tester contracts
    testerContracts.activePool = await ActivePoolTester.new(testerContracts.wstETHTokenMock.address)
    testerContracts.defaultPool = await DefaultPoolTester.new(testerContracts.wstETHTokenMock.address)
    testerContracts.math = await LiquityMathTester.new()
    testerContracts.positionManager = await PositionManagerTester.new()
    testerContracts.functionCaller = await FunctionCaller.new()
    testerContracts.hintHelpers = await HintHelpers.new()
    testerContracts.rToken =  await RTokenTester.new(
      testerContracts.positionManager.address
    )
    return testerContracts
  }

  static async deployLiquityCoreTruffle() {
    const priceFeedTestnet = await PriceFeedTestnet.new()
    const sortedPositions = await SortedPositions.new()
    const positionManager = await PositionManager.new()
    const activePool = await ActivePool.new()
    const defaultPool = await DefaultPool.new()
    const functionCaller = await FunctionCaller.new()
    const hintHelpers = await HintHelpers.new()
    const rToken = await RToken.new(
      positionManager.address
    )
    const coreContracts = {
      priceFeedTestnet,
      rToken,
      sortedPositions,
      positionManager,
      activePool,
      defaultPool,
      functionCaller,
      hintHelpers
    }
    return coreContracts
  }

  static async deployRToken(contracts) {
    contracts.rToken = await RToken.new(
      contracts.positionManager.address
    )
    return contracts
  }

  static async deployRTokenTester(contracts) {
    contracts.rToken = await RTokenTester.new(
      contracts.positionManager.address
    )
    return contracts
  }

  // Connect contracts to their dependencies
  static async connectCoreContracts(contracts, feeRecipient) {

    // set PositionManager addr in SortedPositions
    await contracts.sortedPositions.setParams(
      maxBytes32,
      contracts.positionManager.address
    )

    // set contract addresses in the FunctionCaller
    await contracts.functionCaller.setPositionManagerAddress(contracts.positionManager.address)
    await contracts.functionCaller.setSortedPositionsAddress(contracts.sortedPositions.address)

    // set contracts in the Position Manager
    await contracts.positionManager.setAddresses(
      contracts.activePool.address,
      contracts.defaultPool.address,
      contracts.priceFeedTestnet.address,
      contracts.rToken.address,
      contracts.sortedPositions.address,
      feeRecipient
    )

    // set contracts in the Pools
    await contracts.activePool.setAddresses(
      contracts.positionManager.address,
      contracts.defaultPool.address
    )

    await contracts.defaultPool.setAddresses(
      contracts.positionManager.address
    )

    // set contracts in HintHelpers
    await contracts.hintHelpers.setAddresses(
      contracts.sortedPositions.address,
      contracts.positionManager.address
    )
  }
}
module.exports = DeploymentHelper
