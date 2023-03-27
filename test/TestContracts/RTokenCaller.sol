// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../../contracts/Interfaces/IRToken.sol";

contract RTokenCaller {
    IRToken R;

    function setR(IRToken _R) external {
        R = _R;
    }

    function rMint(address _account, uint _amount) external {
        R.mint(_account, _amount);
    }

    function rBurn(address _account, uint _amount) external {
        R.burn(_account, _amount);
    }

    function rReturnFromPool(address _poolAddress, address _receiver, uint256 _amount ) external {
        R.returnFromPool(_poolAddress, _receiver, _amount);
    }
}
