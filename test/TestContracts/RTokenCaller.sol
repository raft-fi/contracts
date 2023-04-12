// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IRToken} from "../../contracts/Interfaces/IRToken.sol";

contract RTokenCaller {
    IRToken public rToken;

    function setR(IRToken _rToken) external {
        rToken = _rToken;
    }

    function rMint(address _account, uint256 _amount) external {
        rToken.mint(_account, _amount);
    }

    function rBurn(address _account, uint256 _amount) external {
        rToken.burn(_account, _amount);
    }
}
