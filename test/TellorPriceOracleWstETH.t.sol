// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { ITellor } from "../contracts/Dependencies/ITellor.sol";
import { IWstETH } from "../contracts/Dependencies/IWstETH.sol";
import { IPriceOracle } from "../contracts/Oracles/Interfaces/IPriceOracle.sol";
import { TellorPriceOracleWstETH } from "../contracts/Oracles/TellorPriceOracleWstETH.sol";

contract TellorPriceOracleWstETHTest is Test {
    ITellor public constant tellorOracle = ITellor(0xD9157453E2668B2fc45b7A803D3FEF3642430cC0);
    IWstETH public constant wstETH = IWstETH(0x6320cD32aA674d2898A68ec82e869385Fc5f7E2f);
    TellorPriceOracleWstETH public tellorPriceOracleWstETH;

    function setUp() public {
        vm.createSelectFork("goerli", 8_946_759);

        tellorPriceOracleWstETH = new TellorPriceOracleWstETH(
            tellorOracle, keccak256(abi.encode("SpotPrice", abi.encode("steth", "usd"))
        ), wstETH, 5e15);
    }

    function testTellorWstETHPrice() public {
        vm.warp(1_681_413_120);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = tellorPriceOracleWstETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, false);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertApproxEqAbs(priceOracleResponse.price, 2_254_051e15, 1e15);
    }

    function testTellorWstETHPriceFrozen() public {
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = tellorPriceOracleWstETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, true);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertEq(priceOracleResponse.price, 0);
    }
}
