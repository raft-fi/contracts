// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { ITellor } from "../contracts/Dependencies/ITellor.sol";
import { IPriceOracle } from "../contracts/Oracles/Interfaces/IPriceOracle.sol";
import { TellorPriceOracle } from "../contracts/Oracles/TellorPriceOracle.sol";

contract TellorPriceOracleSwETHTest is Test {
    ITellor public constant tellorOracle = ITellor(0xD9157453E2668B2fc45b7A803D3FEF3642430cC0);
    TellorPriceOracle public tellorPriceOracleSwETH;

    function setUp() public {
        vm.createSelectFork("mainnet", 18_213_950);

        tellorPriceOracleSwETH = new TellorPriceOracle(
            tellorOracle, keccak256(abi.encode("SpotPrice", abi.encode("sweth", "usd"))), 5e15, 3 hours, 18);
    }

    function testTellorSwETHPrice() public {
        vm.warp(1_695_658_800 + 20 minutes);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = tellorPriceOracleSwETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, false);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertApproxEqAbs(priceOracleResponse.price, 1_631_234e15, 1e15);
    }

    function testTellorSwETHPriceFrozen() public {
        vm.warp(1_695_660_300 + 3 hours);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = tellorPriceOracleSwETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, true);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertEq(priceOracleResponse.price, 0);
    }

    function testCheckDeployedTellorSwETHOracle() public {
        TellorPriceOracle tellorDeployedOracle = TellorPriceOracle(0xd0D35e9172f20636e221954c32123a12cA4FF303);

        assertEq(address(tellorDeployedOracle.tellor()), address(tellorPriceOracleSwETH.tellor()));
        assertEq(tellorDeployedOracle.tellorQueryId(), tellorPriceOracleSwETH.tellorQueryId());
        assertEq(tellorDeployedOracle.DEVIATION(), tellorPriceOracleSwETH.DEVIATION());
        assertEq(tellorDeployedOracle.timeout(), tellorPriceOracleSwETH.timeout());
    }
}
