forge verify-contract 0xF3aF08e3c58d2B6406472e22C16D181Cc0577f2B contracts/Oracles/ChainlinkPriceOracle.sol:ChainlinkPriceOracle --optimizer-runs=200000 --constructor-args $(cast abi-encode "constructor(address,uint256,uint256,uint256,uint256)" 0xF017fcB346A1885194689bA23Eff2fE6fA5C483b 0 93600 18 100000000000000000) --show-standard-json-input > chainlinkPriceOracleCbETH.json