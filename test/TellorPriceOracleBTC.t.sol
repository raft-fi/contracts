// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { ITellor } from "../contracts/Dependencies/ITellor.sol";
import { IPriceOracle } from "../contracts/Oracles/Interfaces/IPriceOracle.sol";
import { TellorPriceOracle } from "../contracts/Oracles/TellorPriceOracle.sol";

contract TellorPriceOracleBTCTest is Test {
    ITellor public constant tellorOracle = ITellor(0xD9157453E2668B2fc45b7A803D3FEF3642430cC0);
    TellorPriceOracle public tellorPriceOracleBTC;

    function setUp() public {
        vm.createSelectFork("mainnet", 18_362_541);

        tellorPriceOracleBTC = new TellorPriceOracle(
            tellorOracle, keccak256(abi.encode("SpotPrice", abi.encode("btc", "usd"))), 5e15, 3 hours, 18);
    }

    /*function testTellorBTCPrice() public {
        vm.warp(1697447040 + 20 minutes);
    IPriceOracle.PriceOracleResponse memory priceOracleResponse = tellorPriceOracleBTC.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, false);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertApproxEqAbs(priceOracleResponse.price, 1_592_030e15, 1e15);
    } */

    function testTellorBTCPriceFrozen() public {
        vm.warp(1_697_447_040 + 3 hours + 1 minutes);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = tellorPriceOracleBTC.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, true);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertEq(priceOracleResponse.price, 0);
    }

    function testCheckDeployedTellorBTCOracle() public {
        TellorPriceOracle tellorDeployedOracle = TellorPriceOracle(0xfcC8d637497eB045393C7706C8Db27aE11239db3);

        assertEq(address(tellorDeployedOracle.tellor()), address(tellorPriceOracleBTC.tellor()));
        assertEq(tellorDeployedOracle.tellorQueryId(), tellorPriceOracleBTC.tellorQueryId());
        assertEq(tellorDeployedOracle.DEVIATION(), tellorPriceOracleBTC.DEVIATION());
        assertEq(tellorDeployedOracle.timeout(), tellorPriceOracleBTC.timeout());
    }
}
