const { expect } = require("chai");
const {
  DataServiceWrapper,
} = require("@redstone-finance/evm-connector/dist/src/wrappers/DataServiceWrapper");

describe("RedstonePriceOracle", function () {
  let redstoneConsumer;
  let redstonePriceOracle;

  beforeEach(async () => {
    // Deploy contracts
    const RedstoneConsumer = await ethers.getContractFactory("RedstoneConsumer");
    redstoneConsumer = await RedstoneConsumer.deploy(ethers.utils.formatBytes32String("SWETH"));

    const RedstonePriceOracle = await ethers.getContractFactory("RedstonePriceOracle");
    redstonePriceOracle = await RedstonePriceOracle.deploy(redstoneConsumer.address, 0);
  });

  it("Get SWETH price securely", async function () {
    const redstonePayload = await (new DataServiceWrapper({
      dataServiceId: "redstone-primary-prod",
      uniqueSignersCount: 3,
      dataFeeds: ["SWETH"]
    }).getRedstonePayloadForManualUsage(redstonePriceOracle));
    
    // Interact with the contract (getting oracle value securely)
    await redstonePriceOracle.setPrice(redstonePayload);

    // Interact with the contract (getting oracle value securely)
    const swethPrice = await redstonePriceOracle.lastPrice();
    expect(swethPrice).to.gt(0);
    const lastUpdateTimestamp = await redstonePriceOracle.lastUpdateTimestamp();
    expect(lastUpdateTimestamp).to.gt(0);
    const isBroken = await redstonePriceOracle.isBrokenOrFrozen();
    expect(isBroken).to.eq(false);
  });

  it("Revert when bad payload is send", async function () {
    // Wrapping the contract
    const redstonePayload = await (new DataServiceWrapper({
      dataServiceId: "redstone-primary-prod",
      uniqueSignersCount: 3,
      dataFeeds: ["SWETH"]
    }).getRedstonePayloadForManualUsage(redstonePriceOracle));
  
    await expect(redstonePriceOracle.setPrice(redstonePayload + "12"))
      .to.be.revertedWithCustomError(redstonePriceOracle, `RedstonePayloadIsInvalid`);
  });
});
