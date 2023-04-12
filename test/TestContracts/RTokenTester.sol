// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {RToken} from "../../contracts/RToken.sol";
import {IPositionManager} from "../../contracts/Interfaces/IPositionManager.sol";

contract RTokenTester is RToken {
    constructor(IPositionManager _positionManager, address _feeRecipient)
        RToken(address(_positionManager), _feeRecipient)
    {}

    function unprotectedMint(address _account, uint256 _amount) external {
        // No check on caller here

        _mint(_account, _amount);
    }

    function unprotectedBurn(address _account, uint256 _amount) external {
        // No check on caller here

        _burn(_account, _amount);
    }

    function unprotectedSendToPool(address _sender, address _poolAddress, uint256 _amount) external {
        // No check on caller here

        _transfer(_sender, _poolAddress, _amount);
    }

    function callInternalApprove(address owner, address spender, uint256 amount) external returns (bool) {
        _approve(owner, spender, amount);
    }
}
