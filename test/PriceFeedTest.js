
const PriceFeed = artifacts.require("./PriceFeedTester.sol")
const MockChainlink = artifacts.require("./MockAggregator.sol")
const MockTellor = artifacts.require("./MockTellor.sol")
const ChainklinkPriceOracle = artifacts.require("./ChainlinkPriceOracle.sol")
const TellorPriceOracle = artifacts.require("./TellorPriceOracle.sol")

const testHelpers = require("../utils/testHelpers.js")
const th = testHelpers.TestHelper

const { dec, toBN } = th

contract('PriceFeed', async accounts => {

  let priceFeed
  let mockChainlink
  let chainlinkPriceOracle
  let tellorPriceOracle

  beforeEach(async () => {
    mockChainlink = await MockChainlink.new()
    MockChainlink.setAsDeployed(mockChainlink)

    mockTellor = await MockTellor.new()
    MockTellor.setAsDeployed(mockTellor)

    chainlinkPriceOracle = await ChainklinkPriceOracle.new(mockChainlink.address)
    ChainklinkPriceOracle.setAsDeployed(chainlinkPriceOracle)

    tellorPriceOracle = await TellorPriceOracle.new(mockTellor.address)
    TellorPriceOracle.setAsDeployed(tellorPriceOracle)

    // Set primary oracle latest and prev round Id's to non-zero
    await mockChainlink.setLatestRoundId(3)
    await mockChainlink.setPrevRoundId(2)

    //Set current and prev prices in both oracles
    await mockChainlink.setPrice(dec(100, 18))
    await mockChainlink.setPrevPrice(dec(100, 18))
    await mockTellor.setPrice(dec(100, 18))

    // Set mock price updateTimes in both oracles to very recent
    const now = await th.getLatestBlockTimestamp(web3)
    await mockChainlink.setUpdateTime(now)
    await mockTellor.setUpdateTime(now)

    priceFeed = await PriceFeed.new(chainlinkPriceOracle.address, tellorPriceOracle.address)
    PriceFeed.setAsDeployed(priceFeed)
  })

  it("Primary oracle working: fetchPrice should return the correct price, taking into account the number of decimal digits on the aggregator", async () => {
    // Oracle price price is 10.00000000
    await mockChainlink.setDecimals(8)
    await mockChainlink.setPrevPrice(dec(1, 9))
    await mockChainlink.setPrice(dec(1, 9))
    await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()
    // Check Raft PriceFeed gives 10, with 18 digit precision
    assert.equal(price, dec(10, 18))

    // Oracle price is 1e9
    await mockChainlink.setDecimals(0)
    await mockChainlink.setPrevPrice(dec(1, 9))
    await mockChainlink.setPrice(dec(1, 9))
    await priceFeed.fetchPrice()
    price = await priceFeed.lastGoodPrice()
    // Check Raft PriceFeed gives 1e9, with 18 digit precision
    assert.isTrue(price.eq(toBN(dec(1, 27))))

    // Oracle price is 0.0001
    await mockChainlink.setDecimals(18)
    const decimals = await mockChainlink.decimals()

    await mockChainlink.setPrevPrice(dec(1, 14))
    await mockChainlink.setPrice(dec(1, 14))
    await priceFeed.fetchPrice()
    price = await priceFeed.lastGoodPrice()
    // Check Raft PriceFeed gives 0.0001 with 18 digit precision
    assert.isTrue(price.eq(toBN(dec(1, 14))))

    // Oracle price is 1234.56789
    await mockChainlink.setDecimals(5)
    await mockChainlink.setPrevPrice(dec(123456789))
    await mockChainlink.setPrice(dec(123456789))
    await priceFeed.fetchPrice()
    price = await priceFeed.lastGoodPrice()
    // Check Raft PriceFeed gives 0.0001 with 18 digit precision
    assert.equal(price, '1234567890000000000000')
  })

  // --- Primary oracle breaks ---
  it("Primary oracle breaks, secondary working: fetchPrice should return the correct secondary oracle price, taking into account secondary oracle 6-digit granularity", async () => {
    // Primary oracle breaks with negative price
    await mockChainlink.setPrevPrice(dec(1, 8))
    await mockChainlink.setPrice("-5000")

    await mockTellor.setPrice(dec(123, 6))
    await mockChainlink.setUpdateTime(0)

    await priceFeed.fetchPrice()

    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(123, 18))

    // Secondary oracle price is 10 at 6-digit precision
    await mockTellor.setPrice(dec(10, 6))
    await priceFeed.fetchPrice()
    price = await priceFeed.lastGoodPrice()
    // Check Raft PriceFeed gives 10, with 18 digit precision
    assert.equal(price, dec(10, 18))

    // Secondary oracle price is 1e9 at 6-digit precision
    await mockTellor.setPrice(dec(1, 15))
    await priceFeed.fetchPrice()
    price = await priceFeed.lastGoodPrice()
    // Check Raft PriceFeed gives 1e9, with 18 digit precision
    assert.equal(price, dec(1, 27))

    // Secondary oracle price is 0.0001 at 6-digit precision
    await mockTellor.setPrice(100)
    await priceFeed.fetchPrice()
    price = await priceFeed.lastGoodPrice()
    // Check Raft PriceFeed gives 0.0001 with 18 digit precision

    assert.equal(price, dec(1, 14))

    // Secondary oracle price is 1234.56789 at 6-digit precision
    await mockTellor.setPrice(dec(1234567890))
    await priceFeed.fetchPrice()
    price = await priceFeed.lastGoodPrice()
    // Check Raft PriceFeed gives 0.0001 with 18 digit precision
    assert.equal(price, '1234567890000000000000')
  })

  it("Primary oracle broken by zero timestamp, secondary oracle working, return secondary oracle price", async () => {

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await mockTellor.setPrice(dec(123, 6))
    await mockChainlink.setUpdateTime(0)

    await priceFeed.fetchPrice()

    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(123, 18))
  })

  it("Primary oracle broken by future timestamp, secondary oracle working, return secondary oracle price", async () => {
    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    const now = await th.getLatestBlockTimestamp(web3)
    const future = toBN(now).add(toBN('1000'))

    await mockTellor.setPrice(dec(123, 6))
    await mockChainlink.setUpdateTime(future)

    await priceFeed.fetchPrice()

    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(123, 18))
  })

  it("Primary oracle broken by negative price, secondary oracle working, return secondary oracle price", async () => {
    await mockChainlink.setPrevPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await mockTellor.setPrice(dec(123, 6))
    await mockChainlink.setPrice("-5000")

    await priceFeed.fetchPrice()

    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(123, 18))
  })

  it("Primary oracle broken - decimals call reverted, secondary oracle working, return secondary oracle price", async () => {
    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await mockTellor.setPrice(dec(123, 6))
    await mockChainlink.setDecimalsRevert()

    await priceFeed.fetchPrice()

    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(123, 18))
  })


  it("Primary oracle latest round call reverted, secondary oracle working, return the secondary oracle price", async () => {
    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await mockTellor.setPrice(dec(123, 6))
    await mockChainlink.setLatestRevert()

    await priceFeed.fetchPrice()

    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(123, 18))
  })


  it("Primary oracle previous round call reverted, secondary oracle working, return secondary oracle Price", async () => {
    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await mockTellor.setPrice(dec(123, 6))
    await mockChainlink.setPrevRevert()

    await priceFeed.fetchPrice()

    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(123, 18))
  })

  // --- Primary oracle timeout ---

  it("Primary oracle frozen, secondary oracle working: return secondary oracle price", async () => {
    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    // Secondary oracle price is recent
    await mockTellor.setUpdateTime(now)
    await mockTellor.setPrice(dec(123, 6))

    await priceFeed.fetchPrice()

    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(123, 18))
  })

  it("Primary oracle frozen, secondary oracle frozen: return last good price", async () => {
    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await mockTellor.setPrice(dec(123, 6))

    await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

    // check secondary oracle price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const tellorUpdateTime = await mockTellor.getTimestampbyRequestIDandIndex(0, 0)
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

    await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()
    // Expect lastGoodPrice has not updated
    assert.equal(price, dec(999, 18))
  })

  it("Primary oracle times out, secondary oracle broken by 0 price: return last good price", async () => {
    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

    await mockTellor.setPrice(0)

    await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()

    // Expect lastGoodPrice has not updated
    assert.equal(price, dec(999, 18))
  })

  it("Primary oracle is out of date by <4hrs: return primary price", async () => {
    await mockChainlink.setPrevPrice(dec(1234, 8))
    await mockChainlink.setPrice(dec(1234, 8))
    await th.fastForwardTime(14340, web3.currentProvider) // fast forward 3hrs 59 minutes

    await priceFeed.fetchPrice()
    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(1234, 18))
  })

  // --- Primary oracle price deviation ---

  it("Primary oracle price drop of >50%, return the secondary oracle price", async () => {
    priceFeed.setLastGoodPrice(dec(2, 18))

    await mockTellor.setPrice(dec(203,4))
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(99999999)  // price drops to 0.99999999: a drop of > 50% from previous

    await priceFeed.fetchPrice()

    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(203, 16))
  })

  it("Primary oracle price drop of 50%, return the primary oracle price", async () => {
    priceFeed.setLastGoodPrice(dec(2, 18))

    await mockTellor.setPrice(dec(203, 4))
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(dec(1, 8))  // price drops to 1

    await priceFeed.fetchPrice()

    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(1, 18))
  })

  it("Primary oracle price drop of <50%, return primary oracle price", async () => {
    priceFeed.setLastGoodPrice(dec(2, 18))

    await mockTellor.setPrice(dec(203, 4))
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(100000001)   // price drops to 1.00000001:  a drop of < 50% from previous

    await priceFeed.fetchPrice()

    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(100000001, 10))
  })

  it("Primary oracle price increase of >100%, return secondary oracle price", async () => {
    priceFeed.setLastGoodPrice(dec(2, 18))

    await mockTellor.setPrice(dec(203, 4))
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(400000001)  // price increases to 4.000000001: an increase of > 100% from previous

    await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(203, 16))
  })

  it("Primary oracle price increase of 100%, return primary oracle price", async () => {
    priceFeed.setLastGoodPrice(dec(2, 18))

    await mockTellor.setPrice(dec(203, 4))
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(dec(4, 8))  // price increases to 4: an increase of 100% from previous

    await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(4, 18))
  })

  it("Primary oracle price increase of <100%, return primary oracle price", async () => {
    priceFeed.setLastGoodPrice(dec(2, 18))

    await mockTellor.setPrice(dec(203, 4))
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(399999999)  // price increases to 3.99999999: an increase of < 100% from previous

    await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(399999999, 10))
  })

  it("Primary oracle price drop of >50% and secondary oracle price matches: return primary oracle price", async () => {
    priceFeed.setLastGoodPrice(dec(2, 18))

    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(99999999)  // price drops to 0.99999999: a drop of > 50% from previous
    await mockTellor.setPrice(999999) // Secondary oracle price drops to same value (at 6 decimals)

    await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(99999999, 10))
  })

  it("Primary oracle price drop of >50% and secondary oracle price within 5% of primary: return secondary oracle price", async () => {
    priceFeed.setLastGoodPrice(dec(2, 18))

    await mockChainlink.setPrevPrice(dec(1000, 8))  // prev price = 1000
    await mockChainlink.setPrice(dec(100, 8))  // price drops to 100: a drop of > 50% from previous
    await mockTellor.setPrice(104999999) // Secondary oracle price drops to 104.99: price difference with new primary oracle price is now just under 5%

    await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(100, 18))
  })

  it("Primary oracle price drop of >50% and secondary oracle live but not within 5% of primary: return secondary oracle price", async () => {
    priceFeed.setLastGoodPrice(dec(2, 18))

    await mockChainlink.setPrevPrice(dec(1000, 8))  // prev price = 1000
    await mockChainlink.setPrice(dec(100, 8))  // price drops to 100: a drop of > 50% from previous
    await mockTellor.setPrice(105000001) // Secondary oracle price drops to 105.000001: price difference with new primary oracle price is now > 5%

    await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()

    assert.equal(price, dec(105000001, 12)) // return secondary oracle price
  })

  it("Primary oracle price drop of >50% and secondary oracle frozen: return last good price", async () => {
    priceFeed.setLastGoodPrice(dec(1200, 18)) // establish a "last good price" from the previous price fetch

    await mockChainlink.setPrevPrice(dec(1000, 8))  // prev price = 1000
    await mockChainlink.setPrice(dec(100, 8))  // price drops to 100: a drop of > 50% from previous
    await mockTellor.setPrice(dec(100, 8))

    // 4 hours pass with no secondary oracle updates
    await th.fastForwardTime(14400, web3.currentProvider)

     // check secondary oracle price timestamp is out of date by > 4 hours
     const now = await th.getLatestBlockTimestamp(web3)
     const tellorUpdateTime = await mockTellor.getTimestampbyRequestIDandIndex(0, 0)
     assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

     await mockChainlink.setUpdateTime(now)

    await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()

    // Check that the returned price is the last good price
    assert.equal(price, dec(1200, 18))
  })

  // --- Primary oracle fails and secondary oracle is broken ---

  it("Primary oracle price drop of >50% and secondary is broken by 0 price: return last good price", async () => {
    priceFeed.setLastGoodPrice(dec(1200, 18)) // establish a "last good price" from the previous price fetch

    await mockTellor.setPrice(dec(1300, 6))

    // Make mock primary oracle price deviate too much
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(99999999)  // price drops to 0.99999999: a drop of > 50% from previous

    // Make mock secondary oracle return 0 price
    await mockTellor.setPrice(0)

    await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()

    // Check that the returned price is in fact the previous price
    assert.equal(price, dec(1200, 18))
  })

  it("Primary oracle price drop of >50% and secondary oracle is broken by 0 timestamp: return last good price", async () => {
    priceFeed.setLastGoodPrice(dec(1200, 18)) // establish a "last good price" from the previous price fetch

    await mockTellor.setPrice(dec(1300, 6))

    // Make mock primary oracle price deviate too much
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(99999999)  // price drops to 0.99999999: a drop of > 50% from previous

    // Make mock secondary oracle return 0 timestamp
    await mockTellor.setUpdateTime(0)

    await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()

    // Check that the returned price is in fact the previous price
    assert.equal(price, dec(1200, 18))
  })

  it("Primary oracle price drop of >50% and secondary oracle is broken by future timestamp: return last good price", async () => {
    priceFeed.setLastGoodPrice(dec(1200, 18)) // establish a "last good price" from the previous price fetch

    await mockTellor.setPrice(dec(1300, 6))

    // Make mock primary oracle price deviate too much
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(99999999)  // price drops to 0.99999999: a drop of > 50% from previous

    // Make mock secondary oracle return a future timestamp
    const now = await th.getLatestBlockTimestamp(web3)
    const future = toBN(now).add(toBN("10000"))
    await mockTellor.setUpdateTime(future)

    await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()

    // Check that the returned price is in fact the previous price
    assert.equal(price, dec(1200, 18))
  })

  it("Primary oracle is working and secondary oracle is working - return primary oracle price", async () => {
    priceFeed.setLastGoodPrice(dec(1200, 18))

    await mockChainlink.setPrevPrice(dec(101, 8))
    await mockChainlink.setPrice(dec(102, 8))

    await mockTellor.setPrice(dec(103, 18))

    await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()

    // Check that the returned price is current primary oracle price
    assert.equal(price, dec(102, 18))
  })

  it("Primary oracle is working and secondary oracle freezes - return primary oracle price", async () => {
    priceFeed.setLastGoodPrice(dec(1200, 18))

    await mockChainlink.setPrevPrice(dec(101, 8))
    await mockChainlink.setPrice(dec(102, 8))

    await mockTellor.setPrice(dec(103, 18))

    // 4 hours pass with no secondary oracle updates
    await th.fastForwardTime(14400, web3.currentProvider)

    // check secondary oracle price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const tellorUpdateTime = await mockTellor.getTimestampbyRequestIDandIndex(0, 0)
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

    await mockChainlink.setUpdateTime(now) // Primary oracle's price is current

    await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()

    // Check that the returned price is current primary oracle price
    assert.equal(price, dec(102, 18))
  })

  it("Primary oracle is working and secondary oracle breaks: return primary oracle price", async () => {
    priceFeed.setLastGoodPrice(dec(1200, 18)) // establish a "last good price" from the previous price fetch

    await mockChainlink.setPrevPrice(dec(101, 8))
    await mockChainlink.setPrice(dec(102, 8))

    await mockTellor.setPrice(0)

    await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()

    // Check that the returned price is current primary oracle price
    assert.equal(price, dec(102, 18))
  })
})

