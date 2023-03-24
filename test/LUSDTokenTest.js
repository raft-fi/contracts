const deploymentHelper = require("../utils/deploymentHelpers.js")

contract('LUSDToken', async accounts => {
  const [alice, bob, carol] = accounts;

  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(997, 1000)

  let lusdTokenTester
  let stabilityPool

    beforeEach(async () => {

      const contracts = await deploymentHelper.deployTesterContractsHardhat()
      const LQTYContracts = await deploymentHelper.deployLQTYContracts(bountyAddress, lpRewardsAddress, multisig)

      await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
      await deploymentHelper.connectLQTYContracts(LQTYContracts)
      await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)

      lusdTokenTester = contracts.lusdToken

      stabilityPool = contracts.stabilityPool

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

    // TODO: Rewrite this test - it should check the actual lusdTokenTester's balance.
    it('sendToPool(): changes balances of Stability pool and user by the correct amounts', async () => {
      const stabilityPool_BalanceBefore = await lusdTokenTester.balanceOf(stabilityPool.address)
      const bob_BalanceBefore = await lusdTokenTester.balanceOf(bob)
      assert.equal(stabilityPool_BalanceBefore, 0)
      assert.equal(bob_BalanceBefore, 100)

      await lusdTokenTester.unprotectedSendToPool(bob, stabilityPool.address, 75)

      const stabilityPool_BalanceAfter = await lusdTokenTester.balanceOf(stabilityPool.address)
      const bob_BalanceAfter = await lusdTokenTester.balanceOf(bob)
      assert.equal(stabilityPool_BalanceAfter, 75)
      assert.equal(bob_BalanceAfter, 25)
    })

    it('returnFromPool(): changes balances of Stability pool and user by the correct amounts', async () => {
      /// --- SETUP --- give pool 100 LUSD
      await lusdTokenTester.unprotectedMint(stabilityPool.address, 100)

      /// --- TEST ---
      const stabilityPool_BalanceBefore = await lusdTokenTester.balanceOf(stabilityPool.address)
      const  bob_BalanceBefore = await lusdTokenTester.balanceOf(bob)
      assert.equal(stabilityPool_BalanceBefore, 100)
      assert.equal(bob_BalanceBefore, 100)

      await lusdTokenTester.unprotectedReturnFromPool(stabilityPool.address, bob, 75)

      const stabilityPool_BalanceAfter = await lusdTokenTester.balanceOf(stabilityPool.address)
      const bob_BalanceAfter = await lusdTokenTester.balanceOf(bob)
      assert.equal(stabilityPool_BalanceAfter, 25)
      assert.equal(bob_BalanceAfter, 175)
    })
  })



contract('Reset chain state', async accounts => {})
