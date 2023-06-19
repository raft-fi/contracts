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
        vm.createSelectFork("mainnet", 17_484_688);

        tellorPriceOracleWETH =
            new TellorPriceOracle(tellorOracle, keccak256(abi.encode("SpotPrice", abi.encode("eth", "usd"))), 5e15);
    }

    function testTellorWETHPrice() public {
        vm.warp(1_686_826_153);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = tellorPriceOracleWETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, false);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertApproxEqAbs(priceOracleResponse.price, 1_636_296_833e12, 1e12);
    }

    function testTellorWETHPriceFrozen() public {
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = tellorPriceOracleWETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, true);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertEq(priceOracleResponse.price, 0);
    }
}
