// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IRTokenL2 } from "./Interfaces/IRTokenL2.sol";
import { WhitelistAddress } from "./WhitelistAddress.sol";

contract RTokenL2 is ERC20, WhitelistAddress, IRTokenL2 {
    // --- Constructor ---

    // solhint-disable-next-line no-empty-blocks
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) { }

    // --- Functions ---

    function mint(address to, uint256 amount) external override checkWhitelist {
        _mint(to, amount);
    }

    function burn(uint256 amount) external override checkWhitelist {
        _burn(msg.sender, amount);
    }
}
