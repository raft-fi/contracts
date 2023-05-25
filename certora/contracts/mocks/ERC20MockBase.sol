// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract ERC20MockBase is IERC20 {
    uint256 private _totalSupply;
    mapping(address => uint256) private _balanceOf;
    mapping(address => mapping(address => uint256)) private _allowance;

    function name() public pure returns (string memory) {
        return "ERC20MockBase";
    }

    function symbol() public pure returns (string memory) {
        return "ERC20MockBase";
    }

    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual returns (uint256) {
        return _balanceOf[account];
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowance[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowance[msg.sender][spender] = amount;

        return true;
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _balanceOf[msg.sender] -= amount;
        _balanceOf[recipient] += amount;

        return true;
    }

    function transferFrom(address from, address recipient, uint256 amount) external override returns (bool) {
        if (_allowance[from][msg.sender] != type(uint256).max) {
            _allowance[from][msg.sender] -= amount;
        }
        _balanceOf[from] -= amount;
        _balanceOf[recipient] += amount;

        return true;
    }

    function mint(address recipient, uint256 amount) external virtual {
        _mint(recipient, amount);
    }

    function burn(address user, uint256 amount) external virtual {
        _burn(user, amount);
    }

    function _mint(address user, uint256 amount) internal {
        _totalSupply += amount;
        _balanceOf[user] += amount;
    }

    function _burn(address user, uint256 amount) internal {
        _totalSupply -= amount;
        _balanceOf[user] -= amount;
    }
}
