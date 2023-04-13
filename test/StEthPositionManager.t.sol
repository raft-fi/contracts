// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStEth} from "../contracts/Dependencies/IStEth.sol";
import {IWstEth} from "../contracts/Dependencies/IWstEth.sol";
import {MathUtils} from "../contracts/Dependencies/MathUtils.sol";
import {IPositionManagerStEth, StEthPositionManager} from "../contracts/StEthPositionManager.sol";
import {TestSetup} from "./utils/TestSetup.t.sol";
import {PositionManagerUtils} from "./utils/PositionManagerUtils.sol";
import {PriceFeedTestnet} from "./TestContracts/PriceFeedTestnet.sol";

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
        positionManager = new StEthPositionManager(
            priceFeed,
            IWstEth(WSTETH_ADDRESS),
            POSITIONS_SIZE,
            LIQUIDATION_PROTOCOL_FEE,
            new address[](0)
        );
        stEth = positionManager.stEth();
    }

    function testGetPositionEth() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory alicePosition = PositionManagerUtils.openPositionStEth({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: IERC20(WSTETH_ADDRESS),
            icr: 150 * MathUtils._100_PERCENT / 100,
            ethType: PositionManagerUtils.ETHType.ETH
        });
        vm.stopPrank();

        uint256 aliceCollateral = positionManager.raftCollateralTokens(IERC20(WSTETH_ADDRESS)).balanceOf(ALICE);
        uint256 aliceDebt = positionManager.raftDebtToken().balanceOf(ALICE);

        assertEq(aliceCollateral, alicePosition.collateral);
        assertEq(aliceDebt, alicePosition.totalDebt);
    }

    function testGetPositionStEth() public {
        _depositETH(ALICE, 50 ether);

        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory alicePosition = PositionManagerUtils.openPositionStEth({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: IERC20(WSTETH_ADDRESS),
            icr: 150 * MathUtils._100_PERCENT / 100,
            ethType: PositionManagerUtils.ETHType.STETH
        });
        vm.stopPrank();

        uint256 aliceCollateral = positionManager.raftCollateralTokens(IERC20(WSTETH_ADDRESS)).balanceOf(ALICE);
        uint256 aliceDebt = positionManager.raftDebtToken().balanceOf(ALICE);

        assertEq(aliceCollateral, alicePosition.collateral);
        assertEq(aliceDebt, alicePosition.totalDebt);
    }

    function testDepositEth() public {
        IERC20 _collateralToken = IERC20(WSTETH_ADDRESS);
        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory result = PositionManagerUtils.openPositionStEth({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: _collateralToken,
            icr: 2 ether,
            ethType: PositionManagerUtils.ETHType.ETH
        });
        vm.stopPrank();

        uint256 positionCollateralBefore = positionManager.raftCollateralTokens(_collateralToken).balanceOf(ALICE);
        assertEq(positionCollateralBefore, result.collateral);

        uint256 positionManagerBalanceBefore = _collateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerBalanceBefore, result.collateral);

        uint256 collateralTopUpAmount = 1 ether;

        vm.startPrank(ALICE);
        uint256 wstEthAmount = stEth.getSharesByPooledEth(collateralTopUpAmount);
        positionManager.managePositionEth{value: collateralTopUpAmount}(0, false, ALICE, ALICE, 0);
        vm.stopPrank();

        uint256 positionCollateralAfter = positionManager.raftCollateralTokens(_collateralToken).balanceOf(ALICE);
        assertEq(positionCollateralAfter, positionCollateralBefore + wstEthAmount);

        uint256 positionManagerBalanceAfter = _collateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerBalanceAfter, positionManagerBalanceBefore + wstEthAmount);
    }

    function testCannotDepositEth() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPositionStEth({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: IERC20(WSTETH_ADDRESS),
            icr: 2 ether,
            ethType: PositionManagerUtils.ETHType.ETH
        });
        vm.stopPrank();

        vm.startPrank(ALICE);
        vm.expectRevert(IPositionManagerStEth.SendEtherFailed.selector);
        positionManager.managePositionEth{value: 0}(0, false, ALICE, ALICE, 0);
        vm.stopPrank();
    }

    function testDepositStEth() public {
        _depositETH(ALICE, 50 ether);

        IERC20 _collateralToken = IERC20(WSTETH_ADDRESS);

        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory result = PositionManagerUtils.openPositionStEth({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: _collateralToken,
            icr: 2 ether,
            ethType: PositionManagerUtils.ETHType.STETH
        });
        vm.stopPrank();

        uint256 positionCollateralBefore = positionManager.raftCollateralTokens(_collateralToken).balanceOf(ALICE);
        assertEq(positionCollateralBefore, result.collateral);

        uint256 positionManagerBalanceBefore = _collateralToken.balanceOf(address(positionManager));
        assertEq(positionManagerBalanceBefore, result.collateral);

        uint256 collateralTopUpAmount = 1 ether;

        vm.startPrank(ALICE);
        uint256 wstEthAmount = stEth.getSharesByPooledEth(collateralTopUpAmount);
        stEth.approve(address(positionManager), collateralTopUpAmount);
        positionManager.managePositionStEth(collateralTopUpAmount, true, 0, false, ALICE, ALICE, 0);
        vm.stopPrank();

        uint256 positionCollateralAfter = positionManager.raftCollateralTokens(_collateralToken).balanceOf(ALICE);
        assertEq(positionCollateralAfter, positionCollateralBefore + wstEthAmount);

        uint256 positionManagerBalanceAfter = _collateralToken.balanceOf(address(positionManager));
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
            icr: 2 ether,
            ethType: PositionManagerUtils.ETHType.STETH
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
        IStEth(address(stEth)).submit{value: _amount}(ALICE);
        vm.stopPrank();
    }
}
