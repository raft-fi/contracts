// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { ITellor } from "../contracts/Dependencies/ITellor.sol";
import { IWstETH } from "../contracts/Dependencies/IWstETH.sol";
import { IPriceOracle } from "../contracts/Oracles/Interfaces/IPriceOracle.sol";
import { TellorPriceOracleWstETH } from "../contracts/Oracles/TellorPriceOracleWstETH.sol";

interface ITellorPriceOracleOld {
    function TIMEOUT() external view returns (uint256);
}

contract TellorPriceOracleWstETHTest is Test {
    ITellor public constant tellorOracle = ITellor(0xD9157453E2668B2fc45b7A803D3FEF3642430cC0);
    IWstETH public constant wstETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    TellorPriceOracleWstETH public tellorPriceOracleWstETH;

    function setUp() public {
        vm.createSelectFork("mainnet", 18_213_950);

        tellorPriceOracleWstETH = new TellorPriceOracleWstETH(
            tellorOracle, keccak256(abi.encode("SpotPrice", abi.encode("steth", "usd"))
        ), wstETH, 5e15, 3 hours, 18);
    }

    function testTellorWstETHPrice() public {
        vm.warp(1_695_658_800 + 20 minutes);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = tellorPriceOracleWstETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, false);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertApproxEqAbs(priceOracleResponse.price, 1_813_682e15, 1e15);
    }

    function testTellorWstETHPriceFrozen() public {
        vm.warp(1_695_723_600 + 3 hours + 1 minutes);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = tellorPriceOracleWstETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, true);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertEq(priceOracleResponse.price, 0);
    }

    function testCheckDeployedTellorWstETHOracle() public {
        TellorPriceOracleWstETH tellorDeployedOracle =
            TellorPriceOracleWstETH(0x79e75665e72B76CfE013E9FE0319D60DA25015b0);

        assertEq(address(tellorDeployedOracle.tellor()), address(tellorPriceOracleWstETH.tellor()));
        assertEq(tellorDeployedOracle.DEVIATION(), tellorPriceOracleWstETH.DEVIATION());
        assertEq(ITellorPriceOracleOld(address(tellorDeployedOracle)).TIMEOUT(), tellorPriceOracleWstETH.timeout());
    }
}
