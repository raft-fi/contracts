// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../Interfaces/IDefaultPool.sol";

contract DefaultPoolDependent {
    event DefaultPoolChanged(IDefaultPool _newDefaultPool);

    IDefaultPool public defaultPool;

    function setDefaultPool(IDefaultPool _defaultPool) internal {
        defaultPool = _defaultPool;
        emit DefaultPoolChanged(_defaultPool);
    }
}
