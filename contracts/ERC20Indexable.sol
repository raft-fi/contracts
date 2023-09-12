// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { ERC20Capped } from "./common/ERC20Capped.sol";
import { IERC20Indexable } from "./Interfaces/IERC20Indexable.sol";
import { PositionManagerDependent } from "./PositionManagerDependent.sol";

contract ERC20Indexable is IERC20Indexable, ERC20Capped, PositionManagerDependent {
    // --- Types ---

    using Fixed256x18 for uint256;

    // --- Constants ---

    uint256 public constant override INDEX_PRECISION = Fixed256x18.ONE;

    // --- Variables ---

    uint256 internal storedIndex;

    // --- Constructor ---

    constructor(
        address positionManager_,
        string memory name_,
        string memory symbol_,
        uint256 cap_
    )
        ERC20(name_, symbol_)
        ERC20Capped(cap_)
        PositionManagerDependent(positionManager_)
    {
        storedIndex = INDEX_PRECISION;
        emit ERC20IndexableDeployed(positionManager_);
    }

    // --- Functions ---

    function mint(address to, uint256 amount) public virtual override onlyPositionManager {
        _mint(to, amount.divUp(storedIndex));
    }

    function burn(address from, uint256 amount) public virtual override onlyPositionManager {
        _burn(from, amount == type(uint256).max ? ERC20.balanceOf(from) : amount.divUp(storedIndex));
    }

    function setIndex(uint256 backingAmount) public virtual override onlyPositionManager {
        uint256 supply = ERC20.totalSupply();
        uint256 newIndex = (backingAmount == 0 && supply == 0) ? INDEX_PRECISION : backingAmount.divUp(supply);
        storedIndex = newIndex;
        emit IndexUpdated(newIndex);
    }

    function currentIndex() public view virtual override returns (uint256) {
        return storedIndex;
    }

    function totalSupply() public view virtual override(IERC20, ERC20) returns (uint256) {
        return ERC20.totalSupply().mulDown(currentIndex());
    }

    function balanceOf(address account) public view virtual override(IERC20, ERC20) returns (uint256) {
        return ERC20.balanceOf(account).mulDown(currentIndex());
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
