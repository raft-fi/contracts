// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface IRTokenL2 {
    // --- Functions ---

    /// @dev Mints `amount` tokens to `to`
    /// @param to The address to mint tokens to
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 amount) external;

    /// @dev Burns `amount` tokens from `msg.sender`
    /// @param amount The amount of tokens to burn
    function burn(uint256 amount) external;
}
