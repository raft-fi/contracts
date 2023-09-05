// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IWhitelistAddress } from "./Interfaces/IWhitelistAddress.sol";

abstract contract WhitelistAddress is Ownable2Step, IWhitelistAddress {
    // --- Variables ---

    mapping(address whitelistAddress => bool isWhitelisted) public override isWhitelisted;

    // --- Modifiers ---

    modifier checkWhitelist() {
        if (!isWhitelisted[msg.sender]) {
            revert AddressIsNotWhitelisted(msg.sender);
        }
        _;
    }

    // --- Functions ---

    function whitelistAddress(address addressForWhitelist, bool whitelisted) external override onlyOwner {
        if (addressForWhitelist == address(0)) {
            revert InvalidWhitelistAddress();
        }
        isWhitelisted[addressForWhitelist] = whitelisted;

        emit AddressWhitelisted(addressForWhitelist, whitelisted);
    }
}
