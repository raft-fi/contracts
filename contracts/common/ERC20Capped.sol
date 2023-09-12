// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @dev Extension of {ERC20} that adds a cap to the supply of tokens.
 */
abstract contract ERC20Capped is ERC20, Ownable2Step {
    uint256 public cap;

    /**
     * @dev Total supply cap has been exceeded.
     */
    error ERC20ExceededCap();

    /**
     * @dev The supplied cap is not a valid cap.
     */
    error ERC20InvalidCap(uint256 cap);

    constructor(uint256 cap_) {
        setCap(cap_);
    }

    /**
     * @dev Sets the value of the `cap`.
     */
    function setCap(uint256 cap_) public onlyOwner {
        if (cap_ == 0) {
            revert ERC20InvalidCap(0);
        }
        cap = cap_;
    }

    /**
     * @dev See {ERC20-_mint}.
     */
    function _mint(address account, uint256 amount) internal virtual override {
        if (totalSupply() + amount > cap) {
            revert ERC20ExceededCap();
        }
        super._mint(account, amount);
    }
}
