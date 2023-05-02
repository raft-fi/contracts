// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ERC20Indexable, ERC20 } from "../../contracts/ERC20Indexable.sol";

contract ERC20IndexableCertora is ERC20Indexable {
    constructor(address positionManager_,
        string memory name_,
        string memory symbol_) ERC20Indexable(positionManager_, name_, symbol_) {
    }
    
    function totalSupplyERC20() public view returns (uint256) {
        return ERC20.totalSupply();
    }

    function balanceOfERC20(address account) public view returns (uint256) {
        return ERC20.balanceOf(account);
    }
}
