// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

// Common interface for the Pools.
interface IPool {

    // --- Events ---

    event CollateralTokenAddressSet(address _collateralToken);
    event ActivePoolAddressChanged(address _newActivePoolAddress);
    event DefaultPoolAddressChanged(address _newDefaultPoolAddress);
    event EtherSent(address _to, uint _amount);

    // --- Functions ---

    function collateralToken() external view returns(address);

    function getETH() external view returns (uint);

    function getRDebt() external view returns (uint);

    function depositCollateral(address _from, uint _amount) external;

    function increaseRDebt(uint _amount) external;

    function decreaseRDebt(uint _amount) external;
}
