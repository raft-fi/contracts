// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVault } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import { OneInchV5BalancerAMM } from "../contracts/AMMs/OneInchV5BalancerAMM.sol";

// solhint-disable max-line-length
contract OneInchV5BalancerAMMTest is Test {
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant AGGREGATION_ROUTER_V5 = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    OneInchV5BalancerAMM public oneInchBalancerAMM;

    function setUp() public {
        vm.createSelectFork("mainnet", 17_622_834);
        oneInchBalancerAMM = new OneInchV5BalancerAMM(AGGREGATION_ROUTER_V5, IVault(BALANCER_VAULT));
    }

    function testOneInchV5Balancer_oneInchFirst() public {
        IERC20 wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
        IERC20 R = IERC20(0x183015a9bA6fF60230fdEaDc3F43b3D788b13e21);
        uint256 swapAmount = 1_234_560_001_234;
        uint256 minReturn = 10_000;
        address fromAddress = 0x5fEC2f34D80ED82370F733043B6A536d7e9D7f8d;

        uint256 wstETHBalBefore = wstETH.balanceOf(fromAddress);
        uint256 RBalBefore = R.balanceOf(fromAddress);

        vm.startPrank(fromAddress);
        wstETH.approve(address(oneInchBalancerAMM), swapAmount);

        uint256 fromAmountOffset = 36;
        /// wstETH --> DAI
        bytes memory swapCalldata =
            hex"0502b1c50000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca00000000000000000000000000000000000000000000000000000011f7182a3e80000000000000000000000000000000000000000000000000006c89b92ee10220000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000180000000000000003b6d0340c5578194d457dcce3f272538d1ad52c68d1ce8498c4b600c";

        IVault.BatchSwapStep[] memory swaps = new IVault.BatchSwapStep[](1);
        swaps[0] = IVault.BatchSwapStep({
            poolId: 0x20a61b948e33879ce7f23e535cc7baa3bc66c5a9000000000000000000000555,
            assetInIndex: 0,
            assetOutIndex: 1,
            amount: 0,
            userData: ""
        });

        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        /// DAI
        assets[1] = R;
        /// R
        uint256 deadline = type(uint256).max;

        bytes memory oneInchData = abi.encode(fromAmountOffset, swapCalldata);
        bytes memory balancerData = abi.encode(swaps, assets, deadline);
        bytes memory ammData =
            abi.encode(IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F), 1, true, oneInchData, balancerData);
        uint256 amountOut = oneInchBalancerAMM.swap(wstETH, R, swapAmount, minReturn, ammData);

        assertEq(wstETHBalBefore - wstETH.balanceOf(fromAddress), swapAmount);
        assertEq(amountOut, R.balanceOf(fromAddress) - RBalBefore);
        assertGe(amountOut, minReturn);
    }

    function testOneInchV5Balancer_balancerFirst() public {
        IERC20 wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
        IERC20 R = IERC20(0x183015a9bA6fF60230fdEaDc3F43b3D788b13e21);
        IERC20 DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        uint256 swapAmount = 1_234_560_001_234;
        uint256 minReturn = 10_000;
        address fromAddress = 0xA07B17c7df2257ae49f26e17Fff1a6dFC206Ca84;

        uint256 RBalBefore = R.balanceOf(fromAddress);
        uint256 DAIBalBefore = DAI.balanceOf(fromAddress);

        vm.startPrank(fromAddress);
        R.approve(address(oneInchBalancerAMM), swapAmount);

        uint256 fromAmountOffset = 36;
        /// wstETH --> DAI
        bytes memory swapCalldata =
            hex"0502b1c50000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca00000000000000000000000000000000000000000000000000000000024caf201000000000000000000000000000000000000000000000000000000de492a9af40000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000180000000000000003b6d0340c5578194d457dcce3f272538d1ad52c68d1ce8498c4b600c";

        IVault.BatchSwapStep[] memory swaps = new IVault.BatchSwapStep[](1);
        swaps[0] = IVault.BatchSwapStep({
            poolId: 0x380aabe019ed2a9c2d632b51eddd30fd804d0fad000200000000000000000554,
            assetInIndex: 0,
            assetOutIndex: 1,
            amount: 0,
            userData: ""
        });

        IERC20[] memory assets = new IERC20[](2);
        assets[0] = R;
        /// R
        assets[1] = wstETH;
        /// wstETH
        uint256 deadline = type(uint256).max;

        bytes memory oneInchData = abi.encode(fromAmountOffset, swapCalldata);
        bytes memory balancerData = abi.encode(swaps, assets, deadline);
        bytes memory ammData = abi.encode(wstETH, 1, false, oneInchData, balancerData);
        uint256 amountOut = oneInchBalancerAMM.swap(R, DAI, swapAmount, minReturn, ammData);

        assertEq(RBalBefore - R.balanceOf(fromAddress), swapAmount);
        assertEq(amountOut, DAI.balanceOf(fromAddress) - DAIBalBefore);
        assertGe(amountOut, minReturn);
    }
}
