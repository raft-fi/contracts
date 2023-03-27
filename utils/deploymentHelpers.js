const SortedTroves = artifacts.require("./SortedTroves.sol")
const TroveManager = artifacts.require("./TroveManager.sol")
const PriceFeedTestnet = artifacts.require("./PriceFeedTestnet.sol")
const RToken = artifacts.require("./RToken.sol")
const ActivePool = artifacts.require("./ActivePool.sol");
const DefaultPool = artifacts.require("./DefaultPool.sol");
const GasPool = artifacts.require("./GasPool.sol")
const CollSurplusPool = artifacts.require("./CollSurplusPool.sol")
const FunctionCaller = artifacts.require("./TestContracts/FunctionCaller.sol")
const BorrowerOperations = artifacts.require("./BorrowerOperations.sol")
const HintHelpers = artifacts.require("./HintHelpers.sol")

const ActivePoolTester = artifacts.require("./ActivePoolTester.sol")
const DefaultPoolTester = artifacts.require("./DefaultPoolTester.sol")
const LiquityMathTester = artifacts.require("./LiquityMathTester.sol")
const BorrowerOperationsTester = artifacts.require("./BorrowerOperationsTester.sol")
const TroveManagerTester = artifacts.require("./TroveManagerTester.sol")
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
    const sortedTroves = await SortedTroves.new()
    const troveManager = await TroveManager.new()
    const wstETHTokenMock = await WstETHTokenMock.new()
    const activePool = await ActivePool.new(wstETHTokenMock.address)
    const gasPool = await GasPool.new()
    const defaultPool = await DefaultPool.new(wstETHTokenMock.address)
    const collSurplusPool = await CollSurplusPool.new(wstETHTokenMock.address)
    const functionCaller = await FunctionCaller.new()
    const borrowerOperations = await BorrowerOperations.new()
    const hintHelpers = await HintHelpers.new()
    const rToken = await RToken.new(
      troveManager.address,
      borrowerOperations.address
    )
    RToken.setAsDeployed(rToken)
    DefaultPool.setAsDeployed(defaultPool)
    PriceFeedTestnet.setAsDeployed(priceFeedTestnet)
    SortedTroves.setAsDeployed(sortedTroves)
    TroveManager.setAsDeployed(troveManager)
    ActivePool.setAsDeployed(activePool)
    GasPool.setAsDeployed(gasPool)
    CollSurplusPool.setAsDeployed(collSurplusPool)
    FunctionCaller.setAsDeployed(functionCaller)
    BorrowerOperations.setAsDeployed(borrowerOperations)
    HintHelpers.setAsDeployed(hintHelpers)

    const coreContracts = {
      priceFeedTestnet,
      rToken,
      sortedTroves,
      troveManager,
      wstETHTokenMock,
      activePool,
      gasPool,
      defaultPool,
      collSurplusPool,
      functionCaller,
      borrowerOperations,
      hintHelpers
    }
    return coreContracts
  }

  static async mintR(rToken, to = null, amount = null) {
    to = to || (await ethers.getSigners())[0].address;
    amount = amount ? ethers.BigNumber.from(amount) : ethers.BigNumber.from("1000000000000000000000000")

    const borrowerOperationsAddress = await rToken.borrowerOperations();
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [borrowerOperationsAddress]
    })
    await rToken.mint(to, amount, { from: borrowerOperationsAddress, gasPrice: 0 })

    await hre.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [borrowerOperationsAddress]
    })
  }

  static async deployTesterContractsHardhat() {
    const testerContracts = {}

    // Contract without testers (yet)
    testerContracts.priceFeedTestnet = await PriceFeedTestnet.new()
    testerContracts.sortedTroves = await SortedTroves.new()
    testerContracts.wstETHTokenMock = await WstETHTokenMock.new();
    // Actual tester contracts
    testerContracts.activePool = await ActivePoolTester.new(testerContracts.wstETHTokenMock.address)
    testerContracts.defaultPool = await DefaultPoolTester.new(testerContracts.wstETHTokenMock.address)
    testerContracts.gasPool = await GasPool.new()
    testerContracts.collSurplusPool = await CollSurplusPool.new(testerContracts.wstETHTokenMock.address)
    testerContracts.math = await LiquityMathTester.new()
    testerContracts.borrowerOperations = await BorrowerOperationsTester.new()
    testerContracts.troveManager = await TroveManagerTester.new()
    testerContracts.functionCaller = await FunctionCaller.new()
    testerContracts.hintHelpers = await HintHelpers.new()
    testerContracts.rToken =  await RTokenTester.new(
      testerContracts.troveManager.address,
      testerContracts.borrowerOperations.address
    )
    return testerContracts
  }

  static async deployLiquityCoreTruffle() {
    const priceFeedTestnet = await PriceFeedTestnet.new()
    const sortedTroves = await SortedTroves.new()
    const troveManager = await TroveManager.new()
    const activePool = await ActivePool.new()
    const gasPool = await GasPool.new()
    const defaultPool = await DefaultPool.new()
    const collSurplusPool = await CollSurplusPool.new()
    const functionCaller = await FunctionCaller.new()
    const borrowerOperations = await BorrowerOperations.new()
    const hintHelpers = await HintHelpers.new()
    const rToken = await RToken.new(
      troveManager.address,
      borrowerOperations.address
    )
    const coreContracts = {
      priceFeedTestnet,
      rToken,
      sortedTroves,
      troveManager,
      activePool,
      gasPool,
      defaultPool,
      collSurplusPool,
      functionCaller,
      borrowerOperations,
      hintHelpers
    }
    return coreContracts
  }

  static async deployRToken(contracts) {
    contracts.rToken = await RToken.new(
      contracts.troveManager.address,
      contracts.borrowerOperations.address
    )
    return contracts
  }

  static async deployRTokenTester(contracts) {
    contracts.rToken = await RTokenTester.new(
      contracts.troveManager.address,
      contracts.borrowerOperations.address
    )
    return contracts
  }

  // Connect contracts to their dependencies
  static async connectCoreContracts(contracts, feeRecipient) {

    // set TroveManager addr in SortedTroves
    await contracts.sortedTroves.setParams(
      maxBytes32,
      contracts.troveManager.address,
      contracts.borrowerOperations.address
    )

    // set contract addresses in the FunctionCaller
    await contracts.functionCaller.setTroveManagerAddress(contracts.troveManager.address)
    await contracts.functionCaller.setSortedTrovesAddress(contracts.sortedTroves.address)

    // set contracts in the Trove Manager
    await contracts.troveManager.setAddresses(
      contracts.borrowerOperations.address,
      contracts.activePool.address,
      contracts.defaultPool.address,
      contracts.gasPool.address,
      contracts.collSurplusPool.address,
      contracts.priceFeedTestnet.address,
      contracts.rToken.address,
      contracts.sortedTroves.address,
      feeRecipient
    )

    // set contracts in BorrowerOperations
    await contracts.borrowerOperations.setAddresses(
      contracts.troveManager.address,
      contracts.activePool.address,
      contracts.defaultPool.address,
      contracts.gasPool.address,
      contracts.collSurplusPool.address,
      contracts.priceFeedTestnet.address,
      contracts.sortedTroves.address,
      contracts.rToken.address,
      feeRecipient
    )

    // set contracts in the Pools
    await contracts.activePool.setAddresses(
      contracts.borrowerOperations.address,
      contracts.troveManager.address,
      contracts.defaultPool.address
    )

    await contracts.defaultPool.setAddresses(
      contracts.troveManager.address
    )

    await contracts.collSurplusPool.setAddresses(
      contracts.borrowerOperations.address,
      contracts.troveManager.address,
      contracts.activePool.address,
    )

    // set contracts in HintHelpers
    await contracts.hintHelpers.setAddresses(
      contracts.sortedTroves.address,
      contracts.troveManager.address
    )
  }
}
module.exports = DeploymentHelper
