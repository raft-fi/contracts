// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { PositionManager } from "../../../contracts/PositionManager.sol";
import { ERC20MockBase } from "./ERC20MockBase.sol";

contract ERC20IndexableMockBase is ERC20MockBase {
    using Fixed256x18 for uint256;

    // --- Constants ---

    uint256 public constant INDEX_PRECISION = Fixed256x18.ONE;

    // --- Variables ---

    uint256 public currentIndex;

    function mint(address to, uint256 amount) external override {
        _mint(to, amount.divUp(currentIndex));
    }

    function burn(address from, uint256 amount) external override {
        _burn(from, amount == type(uint256).max ? ERC20MockBase.balanceOf(from) : amount.divUp(currentIndex));
    }

    function setIndex(uint256 backingAmount) external {
        uint256 supply = ERC20MockBase.totalSupply();
        uint256 newIndex = (backingAmount == 0 && supply == 0) ? INDEX_PRECISION : backingAmount.divUp(supply);
        currentIndex = newIndex;
    }

    function totalSupply() public view override returns (uint256) {
        return ERC20MockBase.totalSupply().mulDown(currentIndex);
    }

    function balanceOf(address account) public view override returns (uint256) {
        return ERC20MockBase.balanceOf(account).mulDown(currentIndex);
    }
}
