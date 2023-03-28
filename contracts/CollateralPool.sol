// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Interfaces/IActivePool.sol";
import "./Dependencies/BorrowerOperationsDependent.sol";
import "./Dependencies/TroveManagerDependent.sol";

/// @dev The Collateral Pool holds the collateral tokens.
abstract contract CollateralPool is ICollateralPool {
    IERC20 immutable public override collateralToken;
    uint256 public collateralBalance;

    constructor(IERC20 _collateralToken) {
        collateralToken = _collateralToken;

        emit CollateralTokenAddressSet(_collateralToken);
    }

    function _depositCollateral(address _from, uint _amount) internal {
        collateralToken.transferFrom(_from, address(this), _amount);
        collateralBalance += _amount;
    }
}
