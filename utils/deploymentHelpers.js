const PositionManager = artifacts.require("./PositionManager.sol")
const PriceFeedTestnet = artifacts.require("./PriceFeedTestnet.sol")
const RToken = artifacts.require("./RToken.sol")

const MathUtilsTester = artifacts.require("./MathUtilsTester.sol")
const PositionManagerTester = artifacts.require("./PositionManagerTester.sol")
const RTokenTester = artifacts.require("./RTokenTester.sol")
const WstETHTokenMock = artifacts.require("./WstETHTokenMock.sol")

const { TestHelper: th } = require("./testHelpers.js")
const LIQUIDATION_PROTOCOL_FEE = th.dec(50, 16) // 50%

/* "Liquity core" consists of all contracts in the core Liquity system.

*/
const maxBytes32 = '0x' + 'f'.repeat(64)

class DeploymentHelper {

  static async deployLiquityCore(feeRecipient) {
    const cmdLineArgs = process.argv
    const frameworkPath = cmdLineArgs[1]
    // console.log(`Framework used:  ${frameworkPath}`)

    if (frameworkPath.includes("hardhat")) {
      return this.deployLiquityCoreHardhat(feeRecipient)
    } else if (frameworkPath.includes("truffle")) {
      return this.deployLiquityCoreTruffle()
    }
  }

  static async deployLiquityCoreHardhat(feeRecipient) {
    const priceFeedTestnet = await PriceFeedTestnet.new({ from: feeRecipient })
    const wstETHTokenMock = await WstETHTokenMock.new({ from: feeRecipient })
    const positionManager = await PositionManagerTester.new(priceFeedTestnet.address, wstETHTokenMock.address, maxBytes32, LIQUIDATION_PROTOCOL_FEE, [], { from: feeRecipient })
    const rToken = await RTokenTester.at(await positionManager.rToken(), feeRecipient)
    const math = await MathUtilsTester.new({ from: feeRecipient })
    RTokenTester.setAsDeployed(rToken)
    PriceFeedTestnet.setAsDeployed(priceFeedTestnet)
    PositionManagerTester.setAsDeployed(positionManager)
    MathUtilsTester.setAsDeployed(math)

    const coreContracts = {
      priceFeedTestnet,
      rToken,
      positionManager,
      wstETHTokenMock,
      math
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
    testerContracts.wstETHTokenMock = await WstETHTokenMock.new();
    // Actual tester contracts
    testerContracts.math = await MathUtilsTester.new()
    testerContracts.positionManager = await PositionManagerTester.new(dec(50, 16))
    testerContracts.rToken =  await RTokenTester.new(
      testerContracts.positionManager.address
    )
    return testerContracts
  }

  static async deployLiquityCoreTruffle() {
    const priceFeedTestnet = await PriceFeedTestnet.new()
    const positionManager = await PositionManager.new()
    const rToken = await RToken.new(
      positionManager.address
    )
    const coreContracts = {
      priceFeedTestnet,
      rToken,
      positionManager
    }
    return coreContracts
  }
}
module.exports = DeploymentHelper
