// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface IWhitelistAddress {
    // --- Errors ---

    /// @dev Address is not whitelisted.
    error AddressIsNotWhitelisted(address);

    /// @dev Invalid address for whitelist.
    error InvalidWhitelistAddress();

    // --- Events ---

    /// @dev Address is whitelisted or unwhitelisted.
    /// @param addressForWhitelist Address to whitelist or unwhitelist.
    /// @param whitelisted True if address is whitelisted, false if unwhitelisted.
    event AddressWhitelisted(address indexed addressForWhitelist, bool whitelisted);

    // --- Functions ---

    /// @dev Checks if address is whitelisted.
    /// @param _addressToCheck Address to check is whitelisted.
    function isWhitelisted(address _addressToCheck) external view returns (bool);

    /// @dev Whitelist or unwhitelist address.
    /// @param addressForWhitelist Address to whitelist or unwhitelist.
    /// @param whitelisted True if address is whitelisted, false if unwhitelisted.
    function whitelistAddress(address addressForWhitelist, bool whitelisted) external;
}
