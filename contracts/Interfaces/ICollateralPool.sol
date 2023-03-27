// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICollateralPool {

    // --- Events ---

    event CollateralTokenAddressSet(IERC20 _collateralToken);

    // --- Functions ---

    /// @dev Returns the ETH state variable.
    /// Not necessarily equal to the the contract's raw ETH balance - ether can be forcibly sent to contracts.
    function ETH() external view returns (uint);

    function collateralToken() external view returns(IERC20);

    function depositCollateral(address _from, uint _amount) external;
}
