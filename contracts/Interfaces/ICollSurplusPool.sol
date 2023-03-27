// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IActivePool.sol";
import "./IBorrowerOperations.sol";
import "./ITroveManager.sol";

/// @dev No collateral available to claim.
error NoCollateralAvailable();

/// @dev Caller is neither Active Pool nor Trove Manager.
error CollSurplusPoolInvalidCaller();

interface ICollSurplusPool is ICollateralPool {
    // --- Events ---

    event CollateralTokenAddressSet(address _collateralToken);
    event ActivePoolAddressChanged(address _newActivePoolAddress);

    event CollBalanceUpdated(address indexed _account, uint _newBalance);
    event EtherSent(address _to, uint _amount);

    // --- Contract setters ---

    function setAddresses(
        IBorrowerOperations _borrowerOperations,
        ITroveManager _troveManager,
        IActivePool _activePool
    ) external;

    function getCollateral(address _account) external view returns (uint);

    function accountSurplus(address _account, uint _amount) external;

    function claimColl(address _account) external;
}
