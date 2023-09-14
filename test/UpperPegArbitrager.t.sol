// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { IERC3156FlashLender } from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRToken } from "../contracts/Interfaces/IRToken.sol";
import { ChaiPSM } from "../contracts/PSM/ChaiPSM.sol";
import { ConstantPriceFeed } from "../contracts/common/ConstantPriceFeed.sol";
import { PSMFixedFee } from "../contracts/PSM/FixedFee.sol";
import { IChai } from "../contracts/PSM/IChai.sol";
import { PSMSplitLiquidationCollateral } from "../contracts/common/PSMSplitLiquidationCollateral.sol";
import { UpperPegArbitrager } from "../contracts/PSM/UpperPegArbitrager.sol";
import { PriceFeedTestnet } from "./mocks/PriceFeedTestnet.sol";

contract UpperPegArbitragerTest is Test {
    IERC3156FlashLender public constant lender = IERC3156FlashLender(0x60744434d6339a6B27d73d9Eda62b6F66a0a04FA);
    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IRToken public constant R = IRToken(0x183015a9bA6fF60230fdEaDc3F43b3D788b13e21);
    IChai public constant CHAI = IChai(address(0x06AF07097C9Eeb7fD685c692751D5C66dB49c215));
    address public constant AGGREGATION_ROUTER_V5 = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    address public constant OWNER = address(0xaB40A7e3cEF4AfB323cE23B6565012Ac7c76BFef);
    address public constant DAI_WHALE = address(0x66F62574ab04989737228D18C3624f7FC1edAe14);

    ChaiPSM public chaiPSM;
    PriceFeedTestnet public daiPriceFeed;
    UpperPegArbitrager public upperPegArbitrager;

    function setUp() public {
        vm.createSelectFork("mainnet", 18_026_550);

        daiPriceFeed = new PriceFeedTestnet();
        daiPriceFeed.setPrice(1e18);
        chaiPSM = new ChaiPSM(DAI, R, new PSMFixedFee(1e17, 1e17, daiPriceFeed, 95e16), CHAI);
        vm.startPrank(OWNER);
        chaiPSM.positionManager().addCollateralToken(
            chaiPSM, new ConstantPriceFeed(address(chaiPSM)), new PSMSplitLiquidationCollateral()
        );
        vm.stopPrank();
        upperPegArbitrager = new UpperPegArbitrager(lender, DAI, chaiPSM, AGGREGATION_ROUTER_V5);
    }

    function testFlashLona() public {
        uint256 amount = 1_000_000e18;

        // This is needed because R price is below peg, so, it is needed more DAI to repay flash loan
        vm.startPrank(DAI_WHALE);
        DAI.transfer(address(upperPegArbitrager), amount / 5);
        vm.stopPrank();
        uint256 ownerBalanceBefore = DAI.balanceOf(upperPegArbitrager.owner());

        // solhint-disable max-line-length
        bytes memory swapCalldata =
            hex"12aa3caf0000000000000000000000003208684f96458c540eb08f6f01b9e9afb2b7d4f0000000000000000000000000183015a9ba6ff60230fdeadc3f43b3d788b13e210000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000003208684f96458c540eb08f6f01b9e9afb2b7d4f00000000000000000000000005991a2df15a8f6a256d3ec51e99254cd3fb576a900000000000000000000000000000000000000000000be951906eba2aa800000000000000000000000000000000000000000000000005d3649594935889a20a10000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009b00000000000000000000000000000000000000000000000000007d00004f00a0fbb7cd060020a61b948e33879ce7f23e535cc7baa3bc66c5a9000000000000000000000555183015a9ba6ff60230fdeadc3f43b3d788b13e216b175474e89094c44da98b954eedeac495271d0f80a06c4eca276b175474e89094c44da98b954eedeac495271d0f1111111254eeb25477b68fb85ed929f73a96058200000000008c4b600c";
        bytes memory extraData = abi.encode(0, swapCalldata);
        // solhint-enable max-line-length

        upperPegArbitrager.flashBorrow(amount, extraData);

        uint256 profit = DAI.balanceOf(upperPegArbitrager.owner()) - ownerBalanceBefore;
        assertEq(R.balanceOf(address(upperPegArbitrager)), 0);
        assertGt(profit, 0);
        assertLt(profit, amount / 5);
    }
}
