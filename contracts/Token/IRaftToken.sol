// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

interface IRaftToken is IERC20, IERC20Permit {
    /// @dev Triggered when minting is attempted to a zero address.
    error MintingToZeroAddressNotAllowed();

    /// @dev Triggered when an attempt to mint new tokens is made before the minimum time since deployment has passed.
    error MintingNotAllowedYet();

    /// @dev Triggered when there is not enough time elapsed between two consecutive mints.
    error NotEnoughTimeBetweenMints();

    /// @dev Triggered when the minting amount exceeds the `MINT_CAP`% of total supply.
    /// @param amount The attempted mint amount.
    /// @param cap The maximum allowable mint cap (`MINT_CAP`% of total supply).
    error MintAmountIsGreaterThanCap(uint256 amount, uint256 cap);

    /// @dev Triggered when an attempt is made to rename the token with an empty name.
    error NewTokenNameIsEmpty();

    /// @dev Triggered when an attempt is made to assign an empty symbol to the token.
    error NewTokenSymbolIsEmpty();

    /// @dev Emitted when the token is renamed.
    /// @param name The new name of the token.
    /// @param symbol The new symbol of the token.
    event TokenRenamed(string name, string symbol);

    /// @dev Emitted when tokens are rescued from the contract.
    /// @param token The address of the token being rescued.
    /// @param to The address receiving the rescued tokens.
    /// @param amount The amount of tokens rescued.
    event TokensRescued(IERC20 token, address to, uint256 amount);

    /// @dev Returns the initial token supply minted upon deployment.
    function INITIAL_SUPPLY() external view returns (uint256);

    /// @dev Returns the minimum time required between mints.
    function MIN_TIME_BETWEEN_MINTS() external view returns (uint256);

    /// @dev Returns the cap on the percentage of the total supply that can be minted during each mint.
    function MINT_CAP() external view returns (uint256);

    /// @dev Returns the timestamp after which minting is allowed.
    function mintingAllowedAfter() external view returns (uint256);

    /// @dev Returns the timestamp of the last minting event.
    function lastMintingTime() external view returns (uint256);

    /// @dev Creates `amount` new tokens for `to`.
    /// @param account The recipient address for the minted tokens.
    /// @param amount The number of tokens to mint.
    function mint(address account, uint256 amount) external;

    /// @dev Destroys `amount` tokens from the caller's balance.
    /// @param amount The number of tokens to burn.
    function burn(uint256 amount) external;

    /// @dev Recovers tokens that have been accidentally sent to the contract.
    /// @param token The address of the token to be recovered.
    /// @param to The address to which the rescued tokens should be sent.
    function rescueTokens(IERC20 token, address to) external;

    /// @dev Changes the name and symbol of the token.
    /// @param name_ The new name for the token.
    /// @param symbol_ The new symbol for the token.
    function renameToken(string calldata name_, string calldata symbol_) external;
}
