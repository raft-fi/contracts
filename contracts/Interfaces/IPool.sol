// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

// Common interface for the Pools.
interface IPool {

    // --- Events ---

    event CollateralTokenAddressSet(address _collateralToken);
    event ETHBalanceUpdated(uint _newBalance);
    event LUSDBalanceUpdated(uint _newBalance);
    event ActivePoolAddressChanged(address _newActivePoolAddress);
    event DefaultPoolAddressChanged(address _newDefaultPoolAddress);
    event StabilityPoolAddressChanged(address _newStabilityPoolAddress);
    event EtherSent(address _to, uint _amount);

    // --- Functions ---

    function collateralToken() external view returns(address);

    function getETH() external view returns (uint);

    function getLUSDDebt() external view returns (uint);

    function depositCollateral(address _from, uint _amount) external;

    function increaseLUSDDebt(uint _amount) external;

    function decreaseLUSDDebt(uint _amount) external;
}
