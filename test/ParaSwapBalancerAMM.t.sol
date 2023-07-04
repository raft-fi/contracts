// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVault } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import { ParaSwapBalancerAMM } from "../contracts/AMMs/ParaSwapBalancerAMM.sol";

// solhint-disable max-line-length
contract ParaSwapBalancerAMMTest is Test {
    address public constant AUGUSTUS_REGISTRY = 0xa68bEA62Dc4034A689AA0F58A76681433caCa663;
    address public constant AUGUSTUS = 0xDEF171Fe48CF0115B1d80b88dc8eAB59176FEe57;
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    ParaSwapBalancerAMM public paraSwapBalancerAMM;

    function setUp() public {
        vm.createSelectFork("mainnet", 17_620_634);
        paraSwapBalancerAMM = new ParaSwapBalancerAMM(AUGUSTUS_REGISTRY, IVault(BALANCER_VAULT));
    }

    function testParaSwapBalancer_paraswapFirst() public {
        IERC20 wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
        IERC20 R = IERC20(0x183015a9bA6fF60230fdEaDc3F43b3D788b13e21);
        uint256 swapAmount = 1_234_560_001_234;
        uint256 minReturn = 10_000;
        address fromAddress = 0x5fEC2f34D80ED82370F733043B6A536d7e9D7f8d;

        uint256 wstETHBalBefore = wstETH.balanceOf(fromAddress);
        uint256 RBalBefore = R.balanceOf(fromAddress);

        vm.startPrank(fromAddress);
        wstETH.approve(address(paraSwapBalancerAMM), swapAmount);

        uint256 fromAmountOffset = 36;
        /// wstETH --> DAI
        bytes memory swapCalldata =
            hex"0b86a4c10000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca00000000000000000000000000000000000000000000000000000011f7182a3e80000000000000000000000000000000000000000000000000000000001c23549000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000001000000000000000000004de5c5578194d457dcce3f272538d1ad52c68d1ce849";

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

        bytes memory paraswapData = abi.encode(AUGUSTUS, fromAmountOffset, swapCalldata);
        bytes memory balancerData = abi.encode(swaps, assets, deadline);
        bytes memory ammData =
            abi.encode(IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F), 1, true, paraswapData, balancerData);
        uint256 amountOut = paraSwapBalancerAMM.swap(wstETH, R, swapAmount, minReturn, ammData);

        assertEq(wstETHBalBefore - wstETH.balanceOf(fromAddress), swapAmount);
        assertEq(amountOut, R.balanceOf(fromAddress) - RBalBefore);
        assertGe(amountOut, minReturn);
    }

    function testParaSwapBalancer_balancerFirst() public {
        IERC20 wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
        IERC20 R = IERC20(0x183015a9bA6fF60230fdEaDc3F43b3D788b13e21);
        IERC20 DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        uint256 swapAmount = 1_234_560_001_234;
        uint256 minReturn = 10_000;
        address fromAddress = 0xA07B17c7df2257ae49f26e17Fff1a6dFC206Ca84;

        uint256 RBalBefore = R.balanceOf(fromAddress);
        uint256 DAIBalBefore = DAI.balanceOf(fromAddress);

        vm.startPrank(fromAddress);
        R.approve(address(paraSwapBalancerAMM), swapAmount);

        uint256 fromAmountOffset = 36;
        /// wstETH --> DAI
        bytes memory swapCalldata =
            hex"0b86a4c10000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca00000000000000000000000000000000000000000000000000000011f7182a3e80000000000000000000000000000000000000000000000000000000001c23549000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000001000000000000000000004de5c5578194d457dcce3f272538d1ad52c68d1ce849";

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

        bytes memory paraswapData = abi.encode(AUGUSTUS, fromAmountOffset, swapCalldata);
        bytes memory balancerData = abi.encode(swaps, assets, deadline);
        bytes memory ammData = abi.encode(wstETH, 1, false, paraswapData, balancerData);
        uint256 amountOut = paraSwapBalancerAMM.swap(R, DAI, swapAmount, minReturn, ammData);

        assertEq(RBalBefore - R.balanceOf(fromAddress), swapAmount);
        assertEq(amountOut, DAI.balanceOf(fromAddress) - DAIBalBefore);
        assertGe(amountOut, minReturn);
    }
}
