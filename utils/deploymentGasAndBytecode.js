// Hardhat script
const SortedPositions = artifacts.require("./SortedPositions.sol")
const PositionManager = artifacts.require("./PositionManager.sol")
const PriceFeed = artifacts.require("./PriceFeed.sol")
const RToken = artifacts.require("./RToken.sol")
const FunctionCaller = artifacts.require("./FunctionCaller.sol")

const HintHelpers = artifacts.require("./HintHelpers.sol")

const LiquityMathTester = artifacts.require("./LiquityMathTester.sol")
const PositionManagerTester = artifacts.require("./PositionManagerTester.sol")
const RTokenTester = artifacts.require("./RTokenTester.sol")

const dh = require("./deploymentHelpers.js")

const coreContractABIs = [
  PriceFeed,
  RToken,
  SortedPositions,
  PositionManager,
  FunctionCaller,
  HintHelpers,
]

const TesterContractABIs = [
  LiquityMathTester,
  PositionManagerTester,
  RTokenTester,
]

const getGasFromContractDeployment = async (contractObject, name) => {
  const txHash = contractObject.transactionHash
  // console.log(`tx hash  of ${name} deployment is is: ${txHash}`)
  const receipt = await ethers.provider.getTransactionReceipt(txHash)
  const gas = receipt.gasUsed
  console.log(`${name}: ${gas}`)
  return gas
}

const getBytecodeSize = (contractABI) => {
  const bytecodeLength = (contractABI.bytecode.length / 2) - 1
  const deployedBytecodeLength = (contractABI.deployedBytecode.length / 2) - 1
  console.log(`${contractABI.contractName}: ${bytecodeLength}`)
  // console.log(`${contractABI.contractName} deployed bytecode length: ${deployedBytecodeLength}`)
}

const getUSDCostFromGasCost = (deploymentGasTotal, gasPriceInGwei, ETHPrice) => {
  const dollarCost = (deploymentGasTotal * gasPriceInGwei * ETHPrice) / 1e9
  console.log(`At gas price ${gasPriceInGwei} GWei, and ETH Price $${ETHPrice} per ETH, the total cost of deployment in USD is: $${dollarCost}`)
}

const logContractDeploymentCosts = async (contracts) => {
  console.log(`Gas costs for deployments: `)
  let totalGasCost = 0
  for (contractName of Object.keys(contracts)) {
    const gasCost = await getGasFromContractDeployment(contracts[contractName], contractName);
    totalGasCost = totalGasCost + Number(gasCost)
  }
  console.log(`Total deployment gas costs: ${totalGasCost}`)
  getUSDCostFromGasCost(totalGasCost, 200, 1850)
}

const logContractObjects = async (contracts) => {
  console.log(`Contract objects addresses:`)
  let totalGasCost = 0
  for (contractName of Object.keys(contracts)) {
    const gasCost = await getGasFromContractDeployment(contracts[contractName], contractName);
    totalGasCost = totalGasCost + Number(gasCost)
  }
}

const logContractBytecodeLengths = (contractABIs) => {
  console.log(`Contract bytecode lengths:`)
  for (abi of contractABIs) {
    getBytecodeSize(abi)
  }
}

// Run script: log deployment gas costs and bytecode lengths for all contracts
async function main() {
  const coreContracts = await dh.deployLiquityCoreHardhat()
  const testerContracts = await dh.deployTesterContractsHardhat()

  await dh.connectCoreContracts(coreContracts)

  console.log(`CORE CONTRACTS`)
  await logContractDeploymentCosts(coreContracts)
  console.log(`\n`)
  logContractBytecodeLengths(coreContractABIs)
  console.log(`\n`)

  console.log(`TESTER CONTRACTS`)
  await logContractDeploymentCosts(testerContracts)
  console.log(`\n`)
  logContractBytecodeLengths(TesterContractABIs)
  console.log(`\n`)

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
