// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStETH} from "./Dependencies/IStETH.sol";
import {IWstETH} from "./Dependencies/IWstETH.sol";
import {IPositionManagerStETH} from "./Interfaces/IPositionManagerStETH.sol";
import {IPriceFeed} from "./Interfaces/IPriceFeed.sol";
import {ISplitLiquidationCollateral} from "./Interfaces/ISplitLiquidationCollateral.sol";
import {PositionManager} from "./PositionManager.sol";

contract PositionManagerStETH is IPositionManagerStETH, PositionManager {
    IWstETH public immutable override wstETH;
    IStETH public immutable override stETH;

    constructor(
        IPriceFeed _priceFeed,
        IWstETH _wstETH,
        uint256 _positionsSize,
        uint256 _liquidationProtocolFee,
        address[] memory delegates,
        ISplitLiquidationCollateral newSplitLiquidationCollateral
    ) PositionManager(_liquidationProtocolFee, delegates, newSplitLiquidationCollateral) {
        wstETH = _wstETH;
        stETH = IStETH(address(_wstETH.stETH()));

        _addCollateralToken(_wstETH, _priceFeed, _positionsSize);
    }

    function managePositionETH(
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external payable override {
        uint256 wstETHBalanceBefore = wstETH.balanceOf(address(this));
        (bool sent,) = address(wstETH).call{value: msg.value}("");
        if (!sent) {
            revert SendingEtherFailed();
        }
        uint256 wstETHBalanceAfter = wstETH.balanceOf(address(this));
        uint256 wstETHAmount = wstETHBalanceAfter - wstETHBalanceBefore;

        _managePosition(
            wstETH,
            msg.sender,
            wstETHAmount,
            true,
            _debtChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _maxFeePercentage,
            false
        );
    }

    function managePositionETH(
        address _borrower,
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external payable override {
        uint256 wstETHBalanceBefore = wstETH.balanceOf(address(this));
        (bool sent,) = address(wstETH).call{value: msg.value}("");
        if (!sent) {
            revert SendingEtherFailed();
        }
        uint256 wstETHBalanceAfter = wstETH.balanceOf(address(this));
        uint256 wstETHAmount = wstETHBalanceAfter - wstETHBalanceBefore;

        _managePosition(
            wstETH,
            _borrower,
            wstETHAmount,
            true,
            _debtChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _maxFeePercentage,
            false
        );
    }

    function managePositionStETH(
        uint256 _collateralChange,
        bool _isCollateralIncrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external override {
        if (_isCollateralIncrease) {
            stETH.transferFrom(msg.sender, address(this), _collateralChange);
            stETH.approve(address(wstETH), _collateralChange);
            uint256 wstETHAmount = wstETH.wrap(_collateralChange);
            _managePosition(
                wstETH,
                msg.sender,
                wstETHAmount,
                _isCollateralIncrease,
                _debtChange,
                _isDebtIncrease,
                _upperHint,
                _lowerHint,
                _maxFeePercentage,
                false
            );
        } else {
            _managePosition(
                wstETH,
                msg.sender,
                _collateralChange,
                _isCollateralIncrease,
                _debtChange,
                _isDebtIncrease,
                _upperHint,
                _lowerHint,
                _maxFeePercentage,
                false
            );
            uint256 stETHAmount = wstETH.unwrap(_collateralChange);
            stETH.transfer(msg.sender, stETHAmount);
        }
    }

    function managePositionStETH(
        address _borrower,
        uint256 _collateralChange,
        bool _isCollateralIncrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external override {
        if (_isCollateralIncrease) {
            stETH.transferFrom(msg.sender, address(this), _collateralChange);
            stETH.approve(address(wstETH), _collateralChange);
            uint256 wstETHAmount = wstETH.wrap(_collateralChange);
            _managePosition(
                wstETH,
                _borrower,
                wstETHAmount,
                _isCollateralIncrease,
                _debtChange,
                _isDebtIncrease,
                _upperHint,
                _lowerHint,
                _maxFeePercentage,
                false
            );
        } else {
            _managePosition(
                wstETH,
                _borrower,
                _collateralChange,
                _isCollateralIncrease,
                _debtChange,
                _isDebtIncrease,
                _upperHint,
                _lowerHint,
                _maxFeePercentage,
                false
            );
            uint256 stETHAmount = wstETH.unwrap(_collateralChange);
            stETH.transfer(msg.sender, stETHAmount);
        }
    }
}
