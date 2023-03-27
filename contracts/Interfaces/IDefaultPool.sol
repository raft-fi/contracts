// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IPool.sol";


interface IDefaultPool is IPool {
    // --- Events ---
    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event DefaultPoolRDebtUpdated(uint _rDebt);
    event DefaultPoolETHBalanceUpdated(uint _ETH);

    // --- Functions ---
    function sendETH(address _to, uint _amount) external;
}
