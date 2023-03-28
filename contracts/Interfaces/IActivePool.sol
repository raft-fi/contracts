// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IDefaultPool.sol";
import "./IPool.sol";
import "./IPositionManager.sol";

interface IActivePool is IPool {
    // --- Events ---
    event ActivePoolRDebtUpdated(uint _rDebt);
    event ActivePoolCollateralTokenBalanceUpdated(uint _collateralBalance);

    // --- Functions ---
    function setAddresses(
        IPositionManager _positionManager,
        IDefaultPool _defaultPool
    ) external;

    function withdrawCollateral(address _account, uint _amount) external;
}
