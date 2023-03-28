// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IPool.sol";
import "./IPositionManager.sol";

interface IDefaultPool is IPool {
    // --- Events ---
    event PositionManagerAddressChanged(address _newPositionManagerAddress);
    event DefaultPoolRDebtUpdated(uint _rDebt);
    event DefaultPoolCollateralTokenBalanceUpdated(uint _collateralBalance);

    // --- Functions ---
    function setAddresses(IPositionManager _positionManager) external;

    function withdrawCollateral(address _to, uint _amount) external;
}
