const deploymentHelper = require("../utils/deploymentHelpers.js")

contract('LUSDToken', async accounts => {
  const [alice, bob, carol] = accounts;

  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(997, 1000)

  let lusdTokenTester

    beforeEach(async () => {

      const contracts = await deploymentHelper.deployTesterContractsHardhat()
      const LQTYContracts = await deploymentHelper.deployLQTYContracts(bountyAddress, lpRewardsAddress, multisig)

      await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
      await deploymentHelper.connectLQTYContracts(LQTYContracts)
      await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)

      lusdTokenTester = contracts.lusdToken

      await lusdTokenTester.unprotectedMint(alice, 150)
      await lusdTokenTester.unprotectedMint(bob, 100)
      await lusdTokenTester.unprotectedMint(carol, 50)
    })

    it('mint(): issues correct amount of tokens to the given address', async () => {
      const alice_balanceBefore = await lusdTokenTester.balanceOf(alice)
      assert.equal(alice_balanceBefore, 150)

      await lusdTokenTester.unprotectedMint(alice, 100)

      const alice_BalanceAfter = await lusdTokenTester.balanceOf(alice)
      assert.equal(alice_BalanceAfter, 250)
    })

    it('burn(): burns correct amount of tokens from the given address', async () => {
      const alice_balanceBefore = await lusdTokenTester.balanceOf(alice)
      assert.equal(alice_balanceBefore, 150)

      await lusdTokenTester.unprotectedBurn(alice, 70)
      const alice_BalanceAfter = await lusdTokenTester.balanceOf(alice)
      assert.equal(alice_BalanceAfter, 80)
    })
  })



contract('Reset chain state', async accounts => {})
