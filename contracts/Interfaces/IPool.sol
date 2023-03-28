// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ICollateralPool.sol";

// Common interface for the Pools.
interface IPool is ICollateralPool {

    // --- Events ---

    event ActivePoolAddressChanged(address _newActivePoolAddress);
    event DefaultPoolAddressChanged(address _newDefaultPoolAddress);
    event CollateralTokenSent(address _to, uint _amount);

    // --- Functions ---

    function rDebt() external view returns (uint);

    function increaseRDebt(uint _amount) external;

    function decreaseRDebt(uint _amount) external;
}
