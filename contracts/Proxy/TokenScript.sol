// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Dependencies/CheckContract.sol";


contract TokenScript is CheckContract {
    string constant public NAME = "TokenScript";

    IERC20 immutable token;

    constructor(address _tokenAddress) public {
        checkContract(_tokenAddress);
        token = IERC20(_tokenAddress);
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        token.transfer(recipient, amount);
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        token.allowance(owner, spender);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        token.approve(spender, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        token.transferFrom(sender, recipient, amount);
    }
}
