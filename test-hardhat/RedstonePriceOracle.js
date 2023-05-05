const { expect } = require("chai");
const { WrapperBuilder } = require("@redstone-finance/evm-connector");

describe("RedstonePriceOracle", function () {
  let redstoneConsumerIntegration;

  beforeEach(async () => {
    // Deploy contract
    const RedstoneConsumerIntegration = await ethers.getContractFactory("RedstoneConsumerIntegration");
    redstoneConsumerIntegration = await RedstoneConsumerIntegration.deploy();
  });

  it("Get STETH price securely", async function () {
    // Wrapping the contract
    const wrappedContract = WrapperBuilder.wrap(redstoneConsumerIntegration).usingDataService({
      dataServiceId: "redstone-main-demo",
      uniqueSignersCount: 1,
      dataFeeds: ["STETH"],
    }, ["https://d33trozg86ya9x.cloudfront.net"]);

    // Interact with the contract (getting oracle value securely)
    const stethPrice = await wrappedContract.getPrice();
    expect(stethPrice).to.gt(0);
  });
});
