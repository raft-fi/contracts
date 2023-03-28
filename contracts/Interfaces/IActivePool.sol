// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IBorrowerOperations.sol";
import "./IDefaultPool.sol";
import "./IPool.sol";
import "./ITroveManager.sol";

/// @dev Caller is neither Borrower Operations nor Trove Manager.
error ActivePoolInvalidCaller();

interface IActivePool is IPool {
    // --- Events ---
    event ActivePoolRDebtUpdated(uint _rDebt);
    event ActivePoolCollateralTokenBalanceUpdated(uint _collateralBalance);

    // --- Functions ---
    function setAddresses(
        IBorrowerOperations _borrowerOperations,
        ITroveManager _troveManager,
        IDefaultPool _defaultPool
    ) external;

    function withdrawCollateral(address _account, uint _amount) external;
}
