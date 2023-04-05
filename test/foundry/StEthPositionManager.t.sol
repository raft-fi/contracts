// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IStEth } from "../../contracts/Dependencies/IStEth.sol";
import { MathUtils } from "../../contracts/Dependencies/MathUtils.sol";
import { StEthPositionManager } from "../../contracts/StEthPositionManager.sol";
import "./utils/TestSetup.t.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";
import { PriceFeedTestnet } from "../TestContracts/PriceFeedTestnet.sol";

contract StEthPositionManagerTest is TestSetup {
    address public constant WSTETH_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    uint256 public constant POSITIONS_SIZE = 10;
    uint256 public constant LIQUIDATION_PROTOCOL_FEE = 0;

    PriceFeedTestnet public priceFeed;
    StEthPositionManager public positionManager;
    IStEth public stEth;

    function setUp() public override {
        vm.createSelectFork("mainnet", 16_974_953);

        priceFeed = new PriceFeedTestnet();
        positionManager =
            new StEthPositionManager(priceFeed, IERC20(WSTETH_ADDRESS), POSITIONS_SIZE, LIQUIDATION_PROTOCOL_FEE);
        stEth = positionManager.stEth();
    }

    function testGetPositionCollateral() public {
        _depositETH(ALICE, 50 ether);

        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory alicePosition = PositionManagerUtils.openPositionStEth({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: IERC20(WSTETH_ADDRESS),
            icr: 150 * MathUtils._100pct / 100
        });
        vm.stopPrank();

        (,, uint256 aliceStake) = positionManager.positions(ALICE);
        (, uint256 aliceCollateral,) = positionManager.positions(ALICE);
        (uint256 aliceDebt,,) = positionManager.positions(ALICE);

        assertEq(aliceStake, alicePosition.collateral);
        assertEq(aliceCollateral, alicePosition.collateral);
        assertEq(aliceDebt, alicePosition.totalDebt);
    }

    function testDepositStEth() public {
        _depositETH(ALICE, 50 ether);

        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory result = PositionManagerUtils.openPositionStEth({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: IERC20(WSTETH_ADDRESS),
            icr: 2 ether
        });
        vm.stopPrank();

        (,, uint256 aliceStakeBefore) = positionManager.positions(ALICE);
        uint256 totalStakesBefore = positionManager.totalStakes();
        assertEq(totalStakesBefore, aliceStakeBefore);

        (, uint256 positionCollateralBefore,) = positionManager.positions(ALICE);
        assertEq(positionCollateralBefore, result.collateral);

        uint256 positionManagerBalanceBefore = IERC20(WSTETH_ADDRESS).balanceOf(address(positionManager));
        assertEq(positionManagerBalanceBefore, result.collateral);

        uint256 collateralTopUpAmount = 1 ether;

        vm.startPrank(ALICE);
        uint256 wstEthAmount = stEth.getSharesByPooledEth(collateralTopUpAmount);
        stEth.approve(address(positionManager), collateralTopUpAmount);
        positionManager.managePositionStEth(collateralTopUpAmount, true, 0, false, ALICE, ALICE, 0);
        vm.stopPrank();

        (,, uint256 aliceStakeAfter) = positionManager.positions(ALICE);
        uint256 totalStakesAfter = positionManager.totalStakes();
        assertEq(aliceStakeAfter, aliceStakeBefore + wstEthAmount);
        assertEq(totalStakesAfter, totalStakesBefore + wstEthAmount);

        (, uint256 positionCollateralAfter,) = positionManager.positions(ALICE);
        assertEq(positionCollateralAfter, positionCollateralBefore + wstEthAmount);

        uint256 positionManagerBalanceAfter = IERC20(WSTETH_ADDRESS).balanceOf(address(positionManager));
        assertEq(positionManagerBalanceAfter, positionManagerBalanceBefore + wstEthAmount);
    }

    // Sends the correct amount of stEth to the user
    function testWithdrawStEth() public {
        _depositETH(ALICE, 50 ether);

        vm.startPrank(ALICE);
        PositionManagerUtils.openPositionStEth({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: IERC20(WSTETH_ADDRESS),
            icr: 2 ether
        });
        vm.stopPrank();

        uint256 aliceBalanceBefore = stEth.balanceOf(ALICE);
        uint256 withdrawAmount = 1 ether;
        uint256 stEthAmount = stEth.getPooledEthByShares(withdrawAmount);

        // Alice withdraws 1 wstEth
        vm.prank(ALICE);
        positionManager.managePositionStEth(withdrawAmount, false, 0, false, ALICE, ALICE, 0);

        uint256 aliceBalanceAfter = stEth.balanceOf(ALICE);
        assertApproxEqAbs(aliceBalanceAfter, aliceBalanceBefore + stEthAmount, 1);
    }

    function _depositETH(address _account, uint256 _amount) private {
        vm.startPrank(_account);
        IStEth(address(stEth)).submit{ value: _amount }(ALICE);
        vm.stopPrank();
    }
}
