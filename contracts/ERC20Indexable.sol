// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Fixed256x18} from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import {IERC20Indexable} from "./Interfaces/IERC20Indexable.sol";
import {PositionManagerDependent} from "./PositionManagerDependent.sol";

contract ERC20Indexable is IERC20Indexable, ERC20, PositionManagerDependent {
    // --- Types ---

    using Fixed256x18 for uint256;

    // --- Constants ---

    uint256 public constant override INDEX_PRECISION = Fixed256x18.ONE;

    // --- Variables ---

    uint256 public override currentIndex;

    // --- Constructor ---

    constructor(address positionManager, string memory name, string memory symbol)
        ERC20(name, symbol)
        PositionManagerDependent(positionManager)
    {
        currentIndex = INDEX_PRECISION;
        emit ERC20IndexableDeployed(positionManager);
    }

    // --- Functions ---

    function mint(address to, uint256 amount) external override onlyPositionManager {
        _mint(to, amount.divUp(currentIndex));
    }

    function burn(address from, uint256 amount) external override onlyPositionManager {
        _burn(from, amount == type(uint256).max ? ERC20.balanceOf(from) : amount.divUp(currentIndex));
    }

    function setIndex(uint256 backingAmount) external override onlyPositionManager {
        uint256 supply = ERC20.totalSupply();
        currentIndex = (backingAmount == 0 && supply == 0) ? INDEX_PRECISION : backingAmount.divUp(supply);
    }

    function totalSupply() public view virtual override(IERC20, ERC20) returns (uint256) {
        return ERC20.totalSupply().mulDown(currentIndex);
    }

    function balanceOf(address account) public view virtual override(IERC20, ERC20) returns (uint256) {
        return ERC20.balanceOf(account).mulDown(currentIndex);
    }

    function transfer(address, uint256) public virtual override(IERC20, ERC20) returns (bool) {
        revert NotSupported();
    }

    function allowance(address, address) public view virtual override(IERC20, ERC20) returns (uint256) {
        revert NotSupported();
    }

    function approve(address, uint256) public virtual override(IERC20, ERC20) returns (bool) {
        revert NotSupported();
    }

    function transferFrom(address, address, uint256) public virtual override(IERC20, ERC20) returns (bool) {
        revert NotSupported();
    }

    function increaseAllowance(address, uint256) public virtual override returns (bool) {
        revert NotSupported();
    }

    function decreaseAllowance(address, uint256) public virtual override returns (bool) {
        revert NotSupported();
    }
}
