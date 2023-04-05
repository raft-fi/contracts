// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IStEth } from "../Dependencies/IStEth.sol";
import { IPositionManager } from "./IPositionManager.sol";

interface IPositionManagerStEth is IPositionManager {
    /// @dev Return stEth address
    function stEth() external returns (IStEth);

    function managePositionStEth(
        uint256 _collChange,
        bool _isCollIncrease,
        uint256 _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    )
        external;
}
