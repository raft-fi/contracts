// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IPool.sol";


interface IActivePool is IPool {
    // --- Events ---
    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event ActivePoolRDebtUpdated(uint _rDebt);
    event ActivePoolETHBalanceUpdated(uint _ETH);

    // --- Functions ---
    function sendETH(address _account, uint _amount) external;
}
