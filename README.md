# Raft: Smart Contracts

Raft is an immutable, decentralized lending protocol that allows people to take out stablecoin loans against capital-efficient collateral.

R is the first Ethereum USD stablecoin solely backed by stETH (Lido Staked Ether). R provides the most capital-efficient way to borrow using your stETH. R aims to be the stablecoin of choice within the decentralized ecosystem, with deep liquidity across many trading pairs and a stable peg.

This repository contains the Raft smart contracts written in Solidity. To learn more about Raft, please visit [our website](https://raft.fi) and [docs](https://docs.raft.fi).

## Getting Started

### Prerequisites

To build and test the Raft smart contracts, you will need the following:

- [Solidity](https://docs.soliditylang.org/en/v0.8.19/installing-solidity.html)
- [Foundry](https://github.com/foundry-rs/foundry)
- [Node.js](https://nodejs.org/en/)
- [Yarn](https://yarnpkg.com/)
- [Slither](https://github.com/crytic/slither)

### Installation

Clone the repository with its submodules, set up
[Foundry](https://book.getfoundry.sh/getting-started/installation), and install the dependencies via Yarn:

```bash
yarn install
```

### Testing

To run the tests, run the following command:

```bash
forge test
```

### Static Analysis

To run the Slither static analysis tool, run the following command:

```bash
slither .
```

## Contracts

### Core Contracts

| **Contract**                                                                     | **Description**                                                                                                                                                                                                                                                                                                                                                                                                                         |
| -------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`PositionManager`](contracts/PositionManager.sol)                               | The entry point for managing [positions](https://docs.raft.fi/how-it-works/position). It also handles the logic for [borrowing](https://docs.raft.fi/how-it-works/borrowing) R tokens and [repayment](https://docs.raft.fi/how-it-works/returning/repayment) of the debt, as well as [liquidations](https://docs.raft.fi/how-it-works/returning/liquidation) and [redemptions](https://docs.raft.fi/how-it-works/returning/redemption). |
| [`RToken`](contracts/RToken.sol)                                                 | An ERC-20 token designed to [retain a value of 1 USD](https://docs.raft.fi/about-r). R can be minted and burnt only by `PositionManager`.                                                                                                                                                                                                                                                                                               |
| [`ERC20Indexable`](contracts/ERC20Indexable.sol)                                 | Rebase token which is used as the debt token implementation.                                                                                                                                                                                                                                                                                                                                                                            |
| [`SplitLiquidationCollateral`](contracts/SplitLiquidationCollateral.sol)         | Used by `PositionManager` to calculate how liquidated collateral should be split between the liquidator and the protocol.                                                                                                                                                                                                                                                                                                               |
| [`PriceFeed`](contracts/PriceFeed.sol)                                           | Retrieves asset prices from a primary oracle, using a secondary oracle as a fallback when the primary is unavailable or compromised                                                                                                                                                                                                                                                                                                     |
| [`ChainlinkPriceOracleWstETH`](contracts/Oracles/ChainlinkPriceOracleWstETH.sol) | Chainlink oracle integration contract.                                                                                                                                                                                                                                                                                                                                                                                                  |
| [`TellorPriceOracleWstETH`](contracts/Oracles/TellorPriceOracleWstETH.sol)       | Tellor oracle integration contract.                                                                                                                                                                                                                                                                                                                                                                                                     |

### Periphery Contracts

| **Contract**                                                 | **Description**                                                                                                                                                                      |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [`PositionManagerStETH`](contracts/PositionManagerStETH.sol) | Allows managing positions with ETH or stETH collateral. Responsible for wrapping/unwrapping ETH and stETH into/from wstETH. It has to be whitelisted by a user in `PositionManager`. |
| [`OneStepLeverage`](contracts/OneStepLeverage.sol)           | Facilitates opening, closing, or adjusting leverage on wstETH positions with a single transaction, employing flash mint to streamline the process and reduce transaction complexity. |
| [`OneStepLeverageStETH`](contracts/OneStepLeverageStETH.sol) | Extends the functionality of `OneStepLeverage` to allow using ETH and stETH.                                                                                                         |
| [`FlashMintLiquidator`](contracts/FlashMintLiquidator.sol)   | Facilitates the liquidation of undercollateralized positions in a single transaction, employing flash loans to streamline the process.                                               |
| [`ParaSwapAMM`](contracts/AMMs/ParaSwapAMM.sol)              | ParaSwap integration contract. Can be used by `OneStepLeverage`, `OneStepLeverageStETH` and `FlashMintLiquidator`.                                                                   |
| [`BalancerAMM`](contracts/AMMs/BalancerAMM.sol)              | Balancer integration contract. Can be used by `OneStepLeverage`, `OneStepLeverageStETH` and `FlashMintLiquidator`.                                                                   |
