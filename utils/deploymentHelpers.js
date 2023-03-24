const SortedTroves = artifacts.require("./SortedTroves.sol")
const TroveManager = artifacts.require("./TroveManager.sol")
const PriceFeedTestnet = artifacts.require("./PriceFeedTestnet.sol")
const LUSDToken = artifacts.require("./LUSDToken.sol")
const ActivePool = artifacts.require("./ActivePool.sol");
const DefaultPool = artifacts.require("./DefaultPool.sol");
const GasPool = artifacts.require("./GasPool.sol")
const CollSurplusPool = artifacts.require("./CollSurplusPool.sol")
const FunctionCaller = artifacts.require("./TestContracts/FunctionCaller.sol")
const BorrowerOperations = artifacts.require("./BorrowerOperations.sol")
const HintHelpers = artifacts.require("./HintHelpers.sol")

const LQTYStaking = artifacts.require("./LQTYStaking.sol")
const LQTYToken = artifacts.require("./LQTYToken.sol")
const LockupContractFactory = artifacts.require("./LockupContractFactory.sol")
const CommunityIssuance = artifacts.require("./CommunityIssuance.sol")

const LQTYTokenTester = artifacts.require("./LQTYTokenTester.sol")
const CommunityIssuanceTester = artifacts.require("./CommunityIssuanceTester.sol")
const ActivePoolTester = artifacts.require("./ActivePoolTester.sol")
const DefaultPoolTester = artifacts.require("./DefaultPoolTester.sol")
const LiquityMathTester = artifacts.require("./LiquityMathTester.sol")
const BorrowerOperationsTester = artifacts.require("./BorrowerOperationsTester.sol")
const TroveManagerTester = artifacts.require("./TroveManagerTester.sol")
const LUSDTokenTester = artifacts.require("./LUSDTokenTester.sol")
const WstETHTokenMock = artifacts.require("./WstETHTokenMock.sol")

const th = require("./testHelpers.js").TestHelper

/* "Liquity core" consists of all contracts in the core Liquity system.

LQTY contracts consist of only those contracts related to the LQTY Token:

-the LQTY token
-the Lockup factory and lockup contracts
-the LQTYStaking contract
-the CommunityIssuance contract
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

  static async deployLQTYContracts(bountyAddress, lpRewardsAddress, multisigAddress) {
    const cmdLineArgs = process.argv
    const frameworkPath = cmdLineArgs[1]
    // console.log(`Framework used:  ${frameworkPath}`)

    if (frameworkPath.includes("hardhat")) {
      return this.deployLQTYContractsHardhat(bountyAddress, lpRewardsAddress, multisigAddress)
    } else if (frameworkPath.includes("truffle")) {
      return this.deployLQTYContractsTruffle(bountyAddress, lpRewardsAddress, multisigAddress)
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
    const lusdToken = await LUSDToken.new(
      troveManager.address,
      borrowerOperations.address
    )
    LUSDToken.setAsDeployed(lusdToken)
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
      lusdToken,
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

  static async mintLUSD(lusdToken, to = null, amount = null) {
    to = to || (await ethers.getSigners())[0].address;
    amount = amount ? ethers.BigNumber.from(amount) : ethers.BigNumber.from("1000000000000000000000000")
    
    const borrowerOperationsAddress = await lusdToken.borrowerOperationsAddress();
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [borrowerOperationsAddress]
    })
    await lusdToken.mint(to, amount, { from: borrowerOperationsAddress, gasPrice: 0 })
    
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
    testerContracts.communityIssuance = await CommunityIssuanceTester.new()
    testerContracts.activePool = await ActivePoolTester.new(testerContracts.wstETHTokenMock.address)
    testerContracts.defaultPool = await DefaultPoolTester.new(testerContracts.wstETHTokenMock.address)
    testerContracts.gasPool = await GasPool.new()
    testerContracts.collSurplusPool = await CollSurplusPool.new(testerContracts.wstETHTokenMock.address)
    testerContracts.math = await LiquityMathTester.new()
    testerContracts.borrowerOperations = await BorrowerOperationsTester.new()
    testerContracts.troveManager = await TroveManagerTester.new()
    testerContracts.functionCaller = await FunctionCaller.new()
    testerContracts.hintHelpers = await HintHelpers.new()
    testerContracts.lusdToken =  await LUSDTokenTester.new(
      testerContracts.troveManager.address,
      testerContracts.borrowerOperations.address
    )
    return testerContracts
  }

  static async deployLQTYContractsHardhat(bountyAddress, lpRewardsAddress, multisigAddress) {
    const wstETHTokenMock = await WstETHTokenMock.new()
    const lqtyStaking = await LQTYStaking.new(wstETHTokenMock.address)
    const lockupContractFactory = await LockupContractFactory.new()
    const communityIssuance = await CommunityIssuance.new()

    LQTYStaking.setAsDeployed(lqtyStaking)
    LockupContractFactory.setAsDeployed(lockupContractFactory)
    CommunityIssuance.setAsDeployed(communityIssuance)
    // Deploy LQTY Token, passing Community Issuance and Factory addresses to the constructor
    const lqtyToken = await LQTYToken.new(
      communityIssuance.address,
      lqtyStaking.address,
      lockupContractFactory.address,
      bountyAddress,
      lpRewardsAddress,
      multisigAddress
    )
    LQTYToken.setAsDeployed(lqtyToken)

    const LQTYContracts = {
      lqtyStaking,
      lockupContractFactory,
      communityIssuance,
      lqtyToken
    }
    return LQTYContracts
  }

  static async deployLQTYTesterContractsHardhat(bountyAddress, lpRewardsAddress, multisigAddress) {
    const wstETHTokenMock = await WstETHTokenMock.new()
    const lqtyStaking = await LQTYStaking.new(wstETHTokenMock.address)
    const lockupContractFactory = await LockupContractFactory.new()
    const communityIssuance = await CommunityIssuanceTester.new()

    LQTYStaking.setAsDeployed(lqtyStaking)
    LockupContractFactory.setAsDeployed(lockupContractFactory)
    CommunityIssuanceTester.setAsDeployed(communityIssuance)

    // Deploy LQTY Token, passing Community Issuance and Factory addresses to the constructor
    const lqtyToken = await LQTYTokenTester.new(
      communityIssuance.address,
      lqtyStaking.address,
      lockupContractFactory.address,
      bountyAddress,
      lpRewardsAddress,
      multisigAddress
    )
    LQTYTokenTester.setAsDeployed(lqtyToken)

    const LQTYContracts = {
      lqtyStaking,
      lockupContractFactory,
      communityIssuance,
      lqtyToken
    }
    return LQTYContracts
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
    const lusdToken = await LUSDToken.new(
      troveManager.address,
      borrowerOperations.address
    )
    const coreContracts = {
      priceFeedTestnet,
      lusdToken,
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

  static async deployLQTYContractsTruffle(bountyAddress, lpRewardsAddress, multisigAddress) {
    const lqtyStaking = await lqtyStaking.new()
    const lockupContractFactory = await LockupContractFactory.new()
    const communityIssuance = await CommunityIssuance.new()

    /* Deploy LQTY Token, passing Community Issuance,  LQTYStaking, and Factory addresses
    to the constructor  */
    const lqtyToken = await LQTYToken.new(
      communityIssuance.address,
      lqtyStaking.address,
      lockupContractFactory.address,
      bountyAddress,
      lpRewardsAddress,
      multisigAddress
    )

    const LQTYContracts = {
      lqtyStaking,
      lockupContractFactory,
      communityIssuance,
      lqtyToken
    }
    return LQTYContracts
  }

  static async deployLUSDToken(contracts) {
    contracts.lusdToken = await LUSDToken.new(
      contracts.troveManager.address,
      contracts.borrowerOperations.address
    )
    return contracts
  }

  static async deployLUSDTokenTester(contracts) {
    contracts.lusdToken = await LUSDTokenTester.new(
      contracts.troveManager.address,
      contracts.borrowerOperations.address
    )
    return contracts
  }

  // Connect contracts to their dependencies
  static async connectCoreContracts(contracts, LQTYContracts) {

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
      contracts.lusdToken.address,
      contracts.sortedTroves.address,
      LQTYContracts.lqtyToken.address,
      LQTYContracts.lqtyStaking.address
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
      contracts.lusdToken.address,
      LQTYContracts.lqtyStaking.address
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

  static async connectLQTYContracts(LQTYContracts) {
    // Set LQTYToken address in LCF
    await LQTYContracts.lockupContractFactory.setLQTYTokenAddress(LQTYContracts.lqtyToken.address)
  }

  static async connectLQTYContractsToCore(LQTYContracts, coreContracts) {
    await LQTYContracts.lqtyStaking.setAddresses(
      LQTYContracts.lqtyToken.address,
      coreContracts.lusdToken.address,
      coreContracts.troveManager.address,
      coreContracts.borrowerOperations.address,
      coreContracts.activePool.address
    )

    await LQTYContracts.communityIssuance.setAddresses(
      LQTYContracts.lqtyToken.address,
      th.ZERO_ADDRESS /// TODO: fix
    )
  }

  static async connectUnipool(uniPool, LQTYContracts, uniswapPairAddr, duration) {
    await uniPool.setParams(LQTYContracts.lqtyToken.address, uniswapPairAddr, duration)
  }
}
module.exports = DeploymentHelper
