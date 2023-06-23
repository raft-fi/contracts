// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

interface IWrappedCollateralToken is IERC20, IERC20Permit {
    /// @dev User's balance cannot be larger than `maxBalance`.
    error ExceedsMaxBalance();

    /// @dev Total supply of the token cannot exceed `cap`.
    error ExceedsCap();

    /// @dev Invalid address for whitelist.
    error InvalidWhitelistAddress();

    /// @dev Address is not whitelisted.
    error AddressIsNotWhitelisted(address);

    /// @dev Method not supported.
    error Unsupported();

    /// @dev New `maxBalance` value is set.
    /// @param maxBalance_ Maximum balance of single user.
    event MaxBalanceSet(uint256 maxBalance_);

    /// @dev New `cap` value is set.
    /// @param cap_ Maximum total supply of the token.
    event CapSet(uint256 cap_);

    /// @dev Address is whitelisted or unwhitelisted.
    /// @param addressForWhitelist Address to whitelist or unwhitelist.
    /// @param whitelisted True if address is whitelisted, false if unwhitelisted.
    event AddressWhitelisted(address indexed addressForWhitelist, bool whitelisted);

    /// @dev Maximum balance of single user.
    function maxBalance() external view returns (uint256);

    /// @dev Maximum total supply of the token.
    function cap() external view returns (uint256);

    /// @dev Checks if address is whitelisted.
    /// @param _addressToCheck Address to check is whitelisted.
    function isWhitelisted(address _addressToCheck) external view returns (bool);

    /// @dev Sets new maximum balance of a user.
    function setMaxBalance(uint256 newMaxBalance) external;

    /// @dev Sets new cap for the token.
    function setCap(uint256 newCap) external;

    /// @dev Whitelist or unwhitelist address.
    /// @param addressForWhitelist Address to whitelist or unwhitelist.
    /// @param whitelisted True if address is whitelisted, false if unwhitelisted.
    function whitelistAddress(address addressForWhitelist, bool whitelisted) external;

    /// @dev Mint wrapped token to cover any underlyingTokens that would have been transferred by mistake.
    /// @param account Address to mint wrapped tokens to.
    function recover(address account) external returns (uint256);

    /// @dev Deposits underlying tokens on behalf of user.
    /// @param to Address to receive minted wrapped tokens.
    /// @param accountToCheck Address of the user which token balances we need to check.
    /// @param amount Amount of underlying being deposited.
    function depositForWithAccountCheck(address to, address accountToCheck, uint256 amount) external returns (bool);
}
