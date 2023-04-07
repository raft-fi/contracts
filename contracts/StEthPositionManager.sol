// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IStEth } from "./Dependencies/IStEth.sol";
import { IWstEth } from "./Dependencies/IWstEth.sol";
import { IPositionManagerStEth } from "./Interfaces/IPositionManagerStEth.sol";
import { IPriceFeed } from "./Interfaces/IPriceFeed.sol";
import { PositionManager } from "./PositionManager.sol";

contract StEthPositionManager is IPositionManagerStEth, PositionManager {
    IStEth public immutable override stEth;

    constructor(
        IPriceFeed _priceFeed,
        IERC20 _collateralToken,
        uint256 _positionsSize,
        uint256 _liquidationProtocolFee
    )
        PositionManager(_priceFeed, _collateralToken, _positionsSize, _liquidationProtocolFee)
    {
        stEth = IStEth(address(IWstEth(address(_collateralToken)).stETH()));
    }

    function managePositionEth(
        uint256 _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    )
        external
        payable
        override
    {
        uint256 wstEthBalanceBefore = IWstEth(address(collateralToken)).balanceOf(address(this));
        (bool sent, ) = address(collateralToken).call{value: msg.value}("");
        if (!sent) {
            revert SendEtherFailed();
        }
        uint256 wstEthBalanceAfter = IWstEth(address(collateralToken)).balanceOf(address(this));
        uint256 wstEthAmount = wstEthBalanceAfter - wstEthBalanceBefore;

        _managePosition(
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
    )
        external
        override
    {
        if (_isCollIncrease) {
            stEth.transferFrom(msg.sender, address(this), _collChange);
            stEth.approve(address(collateralToken), _collChange);
            uint256 wstEthAmount = IWstEth(address(collateralToken)).wrap(_collChange);
            _managePosition(
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
                _collChange,
                _isCollIncrease,
                _rChange,
                _isDebtIncrease,
                _upperHint,
                _lowerHint,
                _maxFeePercentage,
                false
            );
            uint256 stEthAmount = IWstEth(address(collateralToken)).unwrap(_collChange);
            stEth.transfer(msg.sender, stEthAmount);
        }
    }
}
