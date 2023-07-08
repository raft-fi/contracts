// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Wrapper } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import { ERC20MockBase } from "./ERC20MockBase.sol";

contract WrappedCollateralTokenMock is ERC20MockBase, ERC20Wrapper {
    /* solhint-disable no-empty-blocks */
    constructor(
        IERC20 underlying_,
        string memory name_,
        string memory symbol_
    )
        ERC20Wrapper(underlying_)
        ERC20(name_, symbol_)
    { }
    /* solhint-enable no-empty-blocks */

    function depositForWithAccountCheck(address to, address, uint256 amount) external returns (bool) {
        underlying.transferFrom(msg.sender, address(this), amount);
        _mint(to, amount);
        return true;
    }

    function withdrawTo(address account, uint256 amount) public override returns (bool) {
        _burn(msg.sender, amount);
        underlying.transfer(account, amount);
        return true;
    }

    function name() public view override(ERC20MockBase, ERC20) returns (string memory) {
        return super.name();
    }

    function symbol() public view override(ERC20MockBase, ERC20) returns (string memory) {
        return super.symbol();
    }

    function balanceOf(address account) public view override(ERC20MockBase, ERC20) returns (uint256) {
        return super.balanceOf(account);
    }

    function totalSupply() public view override(ERC20MockBase, ERC20) returns (uint256) {
        return super.totalSupply();
    }

    function approve(address spender, uint256 amount) public override(ERC20MockBase, ERC20) returns (bool) {
        return super.approve(spender, amount);
    }

    function allowance(address owner, address spender) public view override(ERC20MockBase, ERC20) returns (uint256) {
        return super.allowance(owner, spender);
    }

    function transfer(address recipient, uint256 amount) public override(ERC20MockBase, ERC20) returns (bool) {
        return super.transfer(recipient, amount);
    }

    function transferFrom(
        address from,
        address recipient,
        uint256 amount
    )
        public
        override(ERC20MockBase, ERC20)
        returns (bool)
    {
        return super.transferFrom(from, recipient, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20MockBase, ERC20) {
        super._burn(account, amount);
    }

    function _mint(address account, uint256 amount) internal override(ERC20MockBase, ERC20) {
        super._mint(account, amount);
    }
}
