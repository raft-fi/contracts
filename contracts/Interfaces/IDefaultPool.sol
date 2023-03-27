// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IPool.sol";
import "./ITroveManager.sol";

interface IDefaultPool is IPool {
    // --- Events ---
    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event DefaultPoolRDebtUpdated(uint _rDebt);
    event DefaultPoolETHBalanceUpdated(uint _ETH);

    // --- Functions ---
    function setAddresses(ITroveManager _troveManager) external;

    function sendETH(address _to, uint _amount) external;
}
