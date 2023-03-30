const SortedPositions = artifacts.require("./SortedPositions.sol")
const PositionManager = artifacts.require("./PositionManager.sol")
const PriceFeedTestnet = artifacts.require("./PriceFeedTestnet.sol")
const RToken = artifacts.require("./RToken.sol")

const LiquityMathTester = artifacts.require("./LiquityMathTester.sol")
const PositionManagerTester = artifacts.require("./PositionManagerTester.sol")
const RTokenTester = artifacts.require("./RTokenTester.sol")
const WstETHTokenMock = artifacts.require("./WstETHTokenMock.sol")

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
    const rToken = await RToken.new(
      positionManager.address
    )
    RToken.setAsDeployed(rToken)
    PriceFeedTestnet.setAsDeployed(priceFeedTestnet)
    SortedPositions.setAsDeployed(sortedPositions)
    PositionManager.setAsDeployed(positionManager)

    const coreContracts = {
      priceFeedTestnet,
      rToken,
      sortedPositions,
      positionManager,
      wstETHTokenMock
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
    testerContracts.math = await LiquityMathTester.new()
    testerContracts.positionManager = await PositionManagerTester.new()
    testerContracts.rToken =  await RTokenTester.new(
      testerContracts.positionManager.address
    )
    return testerContracts
  }

  static async deployLiquityCoreTruffle() {
    const priceFeedTestnet = await PriceFeedTestnet.new()
    const sortedPositions = await SortedPositions.new()
    const positionManager = await PositionManager.new()
    const rToken = await RToken.new(
      positionManager.address
    )
    const coreContracts = {
      priceFeedTestnet,
      rToken,
      sortedPositions,
      positionManager
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

    // set contracts in the Position Manager
    await contracts.positionManager.setAddresses(
      contracts.priceFeedTestnet.address,
      contracts.wstETHTokenMock.address,
      contracts.rToken.address,
      contracts.sortedPositions.address,
      feeRecipient
    )
  }
}
module.exports = DeploymentHelper
