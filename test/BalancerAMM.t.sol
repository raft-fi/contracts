// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVault } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import { BalancerAMM } from "../contracts/AMMs/BalancerAMM.sol";

contract BalancerAMMIntegrationTest is Test {
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    BalancerAMM public balancerAMM;

    function setUp() public {
        vm.createSelectFork("mainnet", 17_193_681);
        balancerAMM = new BalancerAMM(IVault(BALANCER_VAULT));
    }

    function testBalancer_swap() public {
        IERC20 tokenIn = IERC20(0xA13a9247ea42D743238089903570127DdA72fE44);
        IERC20 tokenOut = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        uint256 swapAmount = 11e17; // 1.1 tokenIn
        uint256 minReturn = 1e6; // 1 tokenOut
        address fromAddress = 0x43b650399F2E4D6f03503f44042fabA8F7D73470;

        uint256 tokenInBalBefore = tokenIn.balanceOf(fromAddress);
        uint256 tokenOutBalBefore = tokenOut.balanceOf(fromAddress);

        vm.startPrank(fromAddress);
        tokenIn.approve(address(balancerAMM), swapAmount);

        IVault.BatchSwapStep[] memory swaps = new IVault.BatchSwapStep[](2);
        swaps[0] = IVault.BatchSwapStep({
            poolId: 0xa13a9247ea42d743238089903570127dda72fe4400000000000000000000035d,
            assetInIndex: 0,
            assetOutIndex: 1,
            amount: 0,
            userData: ""
        });
        swaps[1] = IVault.BatchSwapStep({
            poolId: 0x82698aecc9e28e9bb27608bd52cf57f704bd1b83000000000000000000000336,
            assetInIndex: 1,
            assetOutIndex: 2,
            amount: 0,
            userData: ""
        });

        IERC20[] memory assets = new IERC20[](3);
        assets[0] = tokenIn;
        assets[1] = IERC20(0x82698aeCc9E28e9Bb27608Bd52cF57f704BD1B83); // intermediary asset
        assets[2] = tokenOut;
        uint256 deadline = type(uint256).max;
        bytes memory extraData = abi.encode(swaps, assets, deadline);

        uint256 amountOut = balancerAMM.swap(tokenIn, tokenOut, swapAmount, minReturn, extraData);

        assertEq(tokenInBalBefore - tokenIn.balanceOf(fromAddress), swapAmount);
        assertEq(amountOut, tokenOut.balanceOf(fromAddress) - tokenOutBalBefore);
        assertGe(amountOut, minReturn);
    }
}
