// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { ITellor } from "../contracts/Dependencies/ITellor.sol";
import { IPriceOracle } from "../contracts/Oracles/Interfaces/IPriceOracle.sol";
import { TellorPriceOracle } from "../contracts/Oracles/TellorPriceOracle.sol";

contract TellorPriceOracleWETHTest is Test {
    ITellor public constant tellorOracle = ITellor(0xD9157453E2668B2fc45b7A803D3FEF3642430cC0);
    TellorPriceOracle public tellorPriceOracleWETH;

    function setUp() public {
        vm.createSelectFork("mainnet", 18_219_257);

        tellorPriceOracleWETH = new TellorPriceOracle(
            tellorOracle, keccak256(abi.encode("SpotPrice", abi.encode("eth", "usd"))), 5e15, 3 hours, 18);
    }

    function testTellorWETHPrice() public {
        vm.warp(1_695_723_600 + 20 minutes);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = tellorPriceOracleWETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, false);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertApproxEqAbs(priceOracleResponse.price, 1_592_030e15, 1e15);
    }

    function testTellorWETHPriceFrozen() public {
        vm.warp(1_695_723_600 + 3 hours + 1 minutes);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = tellorPriceOracleWETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, true);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertEq(priceOracleResponse.price, 0);
    }

    function testCheckDeployedTellorWETHOracle() public {
        TellorPriceOracle tellorDeployedOracle = TellorPriceOracle(0x473ef55253d83AB6921D5C101792982F737390Dd);

        assertEq(address(tellorDeployedOracle.tellor()), address(tellorPriceOracleWETH.tellor()));
        assertEq(tellorDeployedOracle.tellorQueryId(), tellorPriceOracleWETH.tellorQueryId());
        assertEq(tellorDeployedOracle.DEVIATION(), tellorPriceOracleWETH.DEVIATION());
        assertEq(tellorDeployedOracle.timeout(), tellorPriceOracleWETH.timeout());
    }
}
