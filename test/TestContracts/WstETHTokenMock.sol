// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IWstEth} from "../../contracts/Dependencies/IWstEth.sol";

// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.3.0/contracts/mocks/ERC20Mock.sol
// mock class using ERC20
contract WstETHTokenMock is ERC20("Wrapped liquid staked Ether 2.0", "wstETH"), IWstEth {
    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }

    function stETH() external pure override returns (IERC20) {
        return IERC20(address(0));
    }

    function wrap(uint256 _stETHAmount) external returns (uint256) {}

    function unwrap(uint256 _wstETHAmount) external returns (uint256) {}

    function getWstETHByStETH(uint256 _stETHAmount) external pure returns (uint256) {
        return _stETHAmount;
    }

    function getStETHByWstETH(uint256 _wstETHAmount) external pure returns (uint256) {
        return _wstETHAmount;
    }

    function stEthPerToken() external pure returns (uint256) {
        return 1e18;
    }

    function tokensPerStEth() external pure returns (uint256) {
        return 1e18;
    }
}
