// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.3.0/contracts/mocks/ERC20Mock.sol
// mock class using ERC20
contract WstETHTokenMock is ERC20("Wrapped liquid staked Ether 2.0", "wstETH") {
    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }
}
