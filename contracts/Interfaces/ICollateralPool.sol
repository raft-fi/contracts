// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICollateralPool {

    // --- Events ---

    event CollateralTokenAddressSet(IERC20 _collateralToken);

    // --- Functions ---

    /// @dev Returns the collateralBalance state variable (balance of collateralToken)
    function collateralBalance() external view returns (uint);

    function collateralToken() external view returns(IERC20);

    function depositCollateral(address _from, uint _amount) external;
}
