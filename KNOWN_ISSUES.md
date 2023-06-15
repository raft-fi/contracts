# List of Known Issues

### "Centralization risks" that are known and/or explicitly coded into the protocol (e.g., an administrator can upgrade crucial contracts and steal all funds)

### Attacks that require access to leaked private keys or trusted addresses

### Issues that are not responsibly disclosed (issues should typically be reported through our platform)

### Chainlink validation when Chainlink updates the underlying Aggregator contract

In `_getPrevChainlinkResponse`, [`currentRoundID - 1`](https://github.com/raft-fi/contracts/blob/master/contracts/Oracles/ChainlinkPriceOracleWstETH.sol#L101) is passed to fetch the second most recent round data. [Chainlink's docs](https://docs.chain.link/data-feeds/historical-data#roundid-in-proxy) can be a bit confusing/contradictory about this at times. However, if/when Chainlink updates the underlying Aggregator contract, the round ID will jump by a large amount. This happens because the round ID passed is actually a composite of the phase ID of the proxy and the actual round ID in the implementation. Each time the aggregator is updated, the phase ID is incremented and the round ID is reset to 1.

When this update occurs and ChainlinkPriceOracle tries to fetch the price on round 1 of a new aggregator, `_getPrevChainlinkResponse` will attempt to fetch an invalid round which reverts so it will [return an empty prevChainlinkResponse](https://github.com/raft-fi/contracts/blob/master/contracts/Oracles/ChainlinkPriceOracleWstETH.sol#L97). During validation, this gets flagged as broken and reported back to PriceFeed, which will then fall back to the secondary oracle or the last good price. However, once the next round is pushed, it should switch back to using Chainlink automatically (assuming no other validation issues arise).

This issue is not fixed for a few reasons:

1. It could occur quite rarely (in our opinion, once every few years), and it will not function for a maximum of one hour (in which case, we have the secondary oracle and cached price as backup).
2. Attempting to resolve this issue could introduce new issues.
3. In our opinion, this could be resolved by Chainlink.
4. If we find a good solution for this issue in the future, we could change the oracle to a new implementation through DAO (as it is not hardcoded in the code).
