const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")
const PositionManagerTester = artifacts.require("./PositionManagerTester.sol")
const RTokenTester = artifacts.require("./RTokenTester.sol")

const th = testHelpers.TestHelper
const dec = th.dec
const toBN = th.toBN


/* NOTE: Some tests involving ETH redemption fees do not test for specific fee values.
 * Some only test that the fees are non-zero when they should occur.
 *
 * Specific ETH gain values will depend on the final fee schedule used, and the final choices for
 * the parameter BETA in the PositionManager, which is still TBD based on economic modelling.
 *
 */
contract('PositionManager', async accounts => {

  const ZERO_ADDRESS = th.ZERO_ADDRESS
  const [owner, A, B, C, D, E, F] = accounts;

  let priceFeed
  let rToken
  let sortedPositions
  let positionManager
  let wstETHTokenMock

  let contracts

  const getOpenPositionRAmount = async (totalDebt) => th.getOpenPositionRAmount(contracts, totalDebt)

  const getSnapshotsRatio = async () => {
    const ratio = (await positionManager.totalStakesSnapshot())
      .mul(toBN(dec(1, 18)))
      .div((await positionManager.totalCollateralSnapshot()))

    return ratio
  }

  beforeEach(async () => {
    contracts = await deploymentHelper.deployLiquityCore()
    contracts.positionManager = await PositionManagerTester.new()
    contracts.rToken = await RTokenTester.new(
      contracts.positionManager.address
    )

    priceFeed = contracts.priceFeedTestnet
    rToken = contracts.rToken
    sortedPositions = contracts.sortedPositions
    positionManager = contracts.positionManager
    wstETHTokenMock = contracts.wstETHTokenMock

    await deploymentHelper.connectCoreContracts(contracts, owner)

    await th.fillAccountsWithWstETH(contracts, [
      A, B, C, D, E, F
    ])
    await th.fillAccountsWithWstETH(contracts, accounts.slice(10, 20))
  })

  it("A given position's stake decline is negligible with adjustments and tiny liquidations", async () => {
    await priceFeed.setPrice(dec(100, 18))

    // Make 1 mega positions A at ~50% total collateral
    wstETHTokenMock.approve(positionManager.address, dec(2, 29), { from: A})
    await positionManager.openPosition(th._100pct, await getOpenPositionRAmount(dec(1, 31)), ZERO_ADDRESS, ZERO_ADDRESS, dec(2, 29), { from: A })

    // Make 5 large positions B, C, D, E, F at ~10% total collateral
    wstETHTokenMock.approve(positionManager.address, dec(4, 28), { from: B})
    await positionManager.openPosition(th._100pct, await getOpenPositionRAmount(dec(2, 30)), ZERO_ADDRESS, ZERO_ADDRESS, dec(4, 28), { from: B })
    wstETHTokenMock.approve(positionManager.address, dec(4, 28), { from: C})
    await positionManager.openPosition(th._100pct, await getOpenPositionRAmount(dec(2, 30)), ZERO_ADDRESS, ZERO_ADDRESS, dec(4, 28), { from: C })
    wstETHTokenMock.approve(positionManager.address, dec(4, 28), { from: D})
    await positionManager.openPosition(th._100pct, await getOpenPositionRAmount(dec(2, 30)), ZERO_ADDRESS, ZERO_ADDRESS, dec(4, 28), { from: D })
    wstETHTokenMock.approve(positionManager.address, dec(4, 28), { from: E})
    await positionManager.openPosition(th._100pct, await getOpenPositionRAmount(dec(2, 30)), ZERO_ADDRESS, ZERO_ADDRESS, dec(4, 28), { from: E })
    wstETHTokenMock.approve(positionManager.address, dec(4, 28), { from: F})
    await positionManager.openPosition(th._100pct, await getOpenPositionRAmount(dec(2, 30)), ZERO_ADDRESS, ZERO_ADDRESS, dec(4, 28), { from: F })

    // Make 10 tiny positions at relatively negligible collateral (~1e-9 of total)
    const tinyPositions = accounts.slice(10, 20)
    for (account of tinyPositions) {
      wstETHTokenMock.approve(positionManager.address, dec(4, 28), { from: account})
      await positionManager.openPosition(th._100pct, await getOpenPositionRAmount(dec(1, 22)), ZERO_ADDRESS, ZERO_ADDRESS, dec(2, 20), { from: account })
    }

    // liquidate 1 position at ~50% total system collateral
    await priceFeed.setPrice(dec(50, 18))
    await positionManager.liquidate(A)

    console.log(`totalStakesSnapshot after L1: ${await positionManager.totalStakesSnapshot()}`)
    console.log(`totalCollateralSnapshot after L1: ${await positionManager.totalCollateralSnapshot()}`)
    console.log(`Snapshots ratio after L1: ${await getSnapshotsRatio()}`)
    console.log(`B pending ETH reward after L1: ${await positionManager.getPendingCollateralTokenReward(B)}`)
    console.log(`B stake after L1: ${(await positionManager.Positions(B))[2]}`)

    // adjust position B 1 wei: apply rewards
    await priceFeed.setPrice(dec(200, 18))
    await positionManager.adjustPosition(th._100pct, 0, 1, false, ZERO_ADDRESS, ZERO_ADDRESS, 0, {from: B})  // B repays 1 wei
    await priceFeed.setPrice(dec(50, 18))
    console.log(`B stake after A1: ${(await positionManager.Positions(B))[2]}`)
    console.log(`Snapshots ratio after A1: ${await getSnapshotsRatio()}`)

    // Loop over tiny positions, and alternately:
    // - Liquidate a tiny position
    // - Adjust B's collateral by 1 wei
    for (let [idx, position] of tinyPositions.entries()) {
      await positionManager.liquidate(position)
      console.log(`B stake after L${idx + 2}: ${(await positionManager.Positions(B))[2]}`)
      console.log(`Snapshots ratio after L${idx + 2}: ${await getSnapshotsRatio()}`)
      await priceFeed.setPrice(dec(200, 18))
      await positionManager.adjustPosition(th._100pct, 0, 1, false, ZERO_ADDRESS, ZERO_ADDRESS, 0, {from: B})  // A repays 1 wei
      await priceFeed.setPrice(dec(50, 18))
      console.log(`B stake after A${idx + 2}: ${(await positionManager.Positions(B))[2]}`)
    }
  })

  // TODO: stake decline for adjustments with sizable liquidations, for comparison
})
