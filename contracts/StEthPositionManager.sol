// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStEth} from "./Dependencies/IStEth.sol";
import {IWstEth} from "./Dependencies/IWstEth.sol";
import {IPositionManagerStEth} from "./Interfaces/IPositionManagerStEth.sol";
import {IPriceFeed} from "./Interfaces/IPriceFeed.sol";
import {PositionManager} from "./PositionManager.sol";

contract StEthPositionManager is IPositionManagerStEth, PositionManager {
    IWstEth public immutable override wstEth;
    IStEth public immutable override stEth;

    constructor(
        IPriceFeed _priceFeed,
        IWstEth _wstEth,
        uint256 _positionsSize,
        uint256 _liquidationProtocolFee,
        address[] memory delegates
    ) PositionManager(_liquidationProtocolFee, delegates) {
        wstEth = _wstEth;
        stEth = IStEth(address(_wstEth.stETH()));

        _addCollateralToken(_wstEth, _priceFeed, _positionsSize);
    }

    function managePositionEth(
        uint256 _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external payable override {
        uint256 wstEthBalanceBefore = wstEth.balanceOf(address(this));
        (bool sent,) = address(wstEth).call{value: msg.value}("");
        if (!sent) {
            revert SendEtherFailed();
        }
        uint256 wstEthBalanceAfter = wstEth.balanceOf(address(this));
        uint256 wstEthAmount = wstEthBalanceAfter - wstEthBalanceBefore;

        _managePosition(
            wstEth,
            msg.sender,
            wstEthAmount,
            true,
            _rChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _maxFeePercentage,
            false
        );
    }

    function managePositionEth(
        address _borrower,
        uint256 _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external payable override {
        uint256 wstEthBalanceBefore = wstEth.balanceOf(address(this));
        (bool sent,) = address(wstEth).call{value: msg.value}("");
        if (!sent) {
            revert SendEtherFailed();
        }
        uint256 wstEthBalanceAfter = wstEth.balanceOf(address(this));
        uint256 wstEthAmount = wstEthBalanceAfter - wstEthBalanceBefore;

        _managePosition(
            wstEth,
            _borrower,
            wstEthAmount,
            true,
            _rChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _maxFeePercentage,
            false
        );
    }

    function managePositionStEth(
        uint256 _collChange,
        bool _isCollIncrease,
        uint256 _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external override {
        if (_isCollIncrease) {
            stEth.transferFrom(msg.sender, address(this), _collChange);
            stEth.approve(address(wstEth), _collChange);
            uint256 wstEthAmount = wstEth.wrap(_collChange);
            _managePosition(
                wstEth,
                msg.sender,
                wstEthAmount,
                _isCollIncrease,
                _rChange,
                _isDebtIncrease,
                _upperHint,
                _lowerHint,
                _maxFeePercentage,
                false
            );
        } else {
            _managePosition(
                wstEth,
                msg.sender,
                _collChange,
                _isCollIncrease,
                _rChange,
                _isDebtIncrease,
                _upperHint,
                _lowerHint,
                _maxFeePercentage,
                false
            );
            uint256 stEthAmount = wstEth.unwrap(_collChange);
            stEth.transfer(msg.sender, stEthAmount);
        }
    }

    function managePositionStEth(
        address _borrower,
        uint256 _collChange,
        bool _isCollIncrease,
        uint256 _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external override {
        if (_isCollIncrease) {
            stEth.transferFrom(msg.sender, address(this), _collChange);
            stEth.approve(address(wstEth), _collChange);
            uint256 wstEthAmount = wstEth.wrap(_collChange);
            _managePosition(
                wstEth,
                _borrower,
                wstEthAmount,
                _isCollIncrease,
                _rChange,
                _isDebtIncrease,
                _upperHint,
                _lowerHint,
                _maxFeePercentage,
                false
            );
        } else {
            _managePosition(
                wstEth,
                _borrower,
                _collChange,
                _isCollIncrease,
                _rChange,
                _isDebtIncrease,
                _upperHint,
                _lowerHint,
                _maxFeePercentage,
                false
            );
            uint256 stEthAmount = wstEth.unwrap(_collChange);
            stEth.transfer(msg.sender, stEthAmount);
        }
    }
}
