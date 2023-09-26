// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { ITellor } from "../contracts/Dependencies/ITellor.sol";
import { IPriceOracle } from "../contracts/Oracles/Interfaces/IPriceOracle.sol";
import { TellorPriceOracle } from "../contracts/Oracles/TellorPriceOracle.sol";

contract TellorPriceOracleCbETHTest is Test {
    ITellor public constant tellorOracle = ITellor(0xD9157453E2668B2fc45b7A803D3FEF3642430cC0);
    TellorPriceOracle public tellorPriceOracleCbETH;

    function setUp() public {
        vm.createSelectFork("mainnet", 18_214_100);

        tellorPriceOracleCbETH = new TellorPriceOracle(
            tellorOracle, keccak256(abi.encode("SpotPrice", abi.encode("cbeth", "usd"))
        ), 5e15, 3 hours, 18);
    }

    function testTellorCbETHPrice() public {
        vm.warp(1_695_660_610 + 20 minutes);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = tellorPriceOracleCbETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, false);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertApproxEqAbs(priceOracleResponse.price, 1_669_359e15, 1e15);
    }

    function testTellorCbETHPriceFrozen() public {
        vm.warp(1_695_660_610 + 3 hours + 1 minutes);
        IPriceOracle.PriceOracleResponse memory priceOracleResponse = tellorPriceOracleCbETH.getPriceOracleResponse();
        assertEq(priceOracleResponse.isBrokenOrFrozen, true);
        assertEq(priceOracleResponse.priceChangeAboveMax, false);
        assertEq(priceOracleResponse.price, 0);
    }

    function testCheckDeployedTellorCbETHOracle() public {
        TellorPriceOracle tellorDeployedOracle = TellorPriceOracle(0xa37775EC7ED5F9DcB27b40eb50d30b2670dF147b);

        assertEq(address(tellorDeployedOracle.tellor()), address(tellorPriceOracleCbETH.tellor()));
        assertEq(tellorDeployedOracle.tellorQueryId(), tellorPriceOracleCbETH.tellorQueryId());
        assertEq(tellorDeployedOracle.DEVIATION(), tellorPriceOracleCbETH.DEVIATION());
        assertEq(tellorDeployedOracle.timeout(), tellorPriceOracleCbETH.timeout());
    }
}
