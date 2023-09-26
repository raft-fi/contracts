// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { ITellor } from "../contracts/Dependencies/ITellor.sol";
import { IPriceOracle } from "../contracts/Oracles/Interfaces/IPriceOracle.sol";
import { TellorPriceOracle } from "../contracts/Oracles/TellorPriceOracle.sol";

contract TellorPriceOracleRETHTest is Test {
    ITellor public constant tellorOracle = ITellor(0xD9157453E2668B2fc45b7A803D3FEF3642430cC0);
    TellorPriceOracle public tellorPriceOracleRETH;

    function setUp() public {
        vm.createSelectFork("mainnet", 18_213_950);

        tellorPriceOracleRETH = new TellorPriceOracle(
            tellorOracle, keccak256(abi.encode("SpotPrice", abi.encode("reth", "usd"))
        ), 5e15, 2 hours, 18);
    }

    function testTellorRETHPrice() public {
        vm.warp(1_695_658_800 + 20 minutes);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = tellorPriceOracleRETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, false);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertApproxEqAbs(priceOracleResponse.price, 1_723_667e15, 1e15);
    }

    function testTellorRETHPriceFrozen() public {
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = tellorPriceOracleRETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, true);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertEq(priceOracleResponse.price, 0);
    }

    function testCheckDeployedTellorRETHOracle() public {
        TellorPriceOracle tellorDeployedOracle = TellorPriceOracle(0xf9784B938c5b82510708f90941F1aD03169d75BD);

        assertEq(address(tellorDeployedOracle.tellor()), address(tellorPriceOracleRETH.tellor()));
        assertEq(tellorDeployedOracle.tellorQueryId(), tellorPriceOracleRETH.tellorQueryId());
        assertEq(tellorDeployedOracle.DEVIATION(), tellorPriceOracleRETH.DEVIATION());
        assertEq(tellorDeployedOracle.timeout(), tellorPriceOracleRETH.timeout());
    }
}
