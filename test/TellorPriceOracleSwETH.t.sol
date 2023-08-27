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
        vm.createSelectFork("goerli", 9_516_129);

        tellorPriceOracleSwETH =
        new TellorPriceOracle(tellorOracle, keccak256(abi.encode("SpotPrice", abi.encode("sweth", "usd"))), 0, 9 hours);
    }

    function testTellorSwETHPrice() public {
        vm.warp(1_692_011_148);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = tellorPriceOracleSwETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, false);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertApproxEqAbs(priceOracleResponse.price, 1_891_892_195e12, 1e12);
    }

    function testTellorSwETHPriceFrozen() public {
        vm.warp(1_692_011_148 + 9 hours);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = tellorPriceOracleSwETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, true);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertEq(priceOracleResponse.price, 0);
    }
}
