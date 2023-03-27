// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../Interfaces/IActivePool.sol";

contract ActivePoolDependent {
    event ActivePoolChanged(IActivePool _newActivePool);

    IActivePool public activePool;

    function setActivePool(IActivePool _activePool) internal {
        activePool = _activePool;
        emit ActivePoolChanged(_activePool);
    }
}
