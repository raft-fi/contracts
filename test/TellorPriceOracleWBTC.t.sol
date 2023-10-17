// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { ITellor } from "../contracts/Dependencies/ITellor.sol";
import { IPriceOracle } from "../contracts/Oracles/Interfaces/IPriceOracle.sol";
import { TellorPriceOracle } from "../contracts/Oracles/TellorPriceOracle.sol";

contract TellorPriceOracleBTCTest is Test {
    ITellor public constant tellorOracle = ITellor(0xD9157453E2668B2fc45b7A803D3FEF3642430cC0);
    TellorPriceOracle public tellorPriceOracleWBTC;

    function setUp() public {
        vm.createSelectFork("mainnet", 18_363_402);

        tellorPriceOracleWBTC = new TellorPriceOracle(
            tellorOracle, keccak256(abi.encode("SpotPrice", abi.encode("wbtc", "usd"))), 5e15, 3 hours, 28);
    }

    /*
    function testTellorBTCPrice() public {
        vm.warp(1697447040 + 20 minutes);
    IPriceOracle.PriceOracleResponse memory priceOracleResponse = tellorPriceOracleBTC.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, false);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertApproxEqAbs(priceOracleResponse.price, 1_592_030e15, 1e15);
    } 

    function testTellorWBTCPriceFrozen() public {
        vm.warp(1_697_465_926 + 3 hours + 1 minutes);
    IPriceOracle.PriceOracleResponse memory priceOracleResponse = tellorPriceOracleWBTC.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, true);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertEq(priceOracleResponse.price, 0);
    }
    */

    function testCheckDeployedTellorWBTCOracle() public {
        TellorPriceOracle tellorDeployedOracle = TellorPriceOracle(0x843E06D0E9c5DAc7ccbca76d739C4d1265C60098);

        assertEq(address(tellorDeployedOracle.tellor()), address(tellorPriceOracleWBTC.tellor()));
        assertEq(tellorDeployedOracle.tellorQueryId(), tellorPriceOracleWBTC.tellorQueryId());
        assertEq(tellorDeployedOracle.DEVIATION(), tellorPriceOracleWBTC.DEVIATION());
        assertEq(tellorDeployedOracle.timeout(), tellorPriceOracleWBTC.timeout());
        assertEq(tellorDeployedOracle.targetDigits(), tellorPriceOracleWBTC.targetDigits());
    }
}
