// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../LUSDToken.sol";

contract LUSDTokenTester is LUSDToken {

    bytes32 private immutable _PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    constructor(
        address _troveManagerAddress,
        address _stabilityPoolAddress,
        address _borrowerOperationsAddress
    ) public LUSDToken(_troveManagerAddress,
                      _stabilityPoolAddress,
                      _borrowerOperationsAddress) {}

    function unprotectedMint(address _account, uint256 _amount) external {
        // No check on caller here

        _mint(_account, _amount);
    }

    function unprotectedBurn(address _account, uint _amount) external {
        // No check on caller here

        _burn(_account, _amount);
    }

    function unprotectedSendToPool(address _sender,  address _poolAddress, uint256 _amount) external {
        // No check on caller here

        _transfer(_sender, _poolAddress, _amount);
    }

    function unprotectedReturnFromPool(address _poolAddress, address _receiver, uint256 _amount ) external {
        // No check on caller here

        _transfer(_poolAddress, _receiver, _amount);
    }

    function callInternalApprove(address owner, address spender, uint256 amount) external returns (bool) {
        _approve(owner, spender, amount);
    }
}
