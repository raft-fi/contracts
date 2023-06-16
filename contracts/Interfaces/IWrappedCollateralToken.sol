// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

interface IWrappedCollateralToken is IERC20, IERC20Permit {
    /// @dev User's balance cannot be larger than `maxBalance`.
    error ExceedsMaxBalance();

    /// @dev Total supply of the token cannot exceed `cap`.
    error ExceedsCap();

    /// @dev New `maxBalance` value is set.
    /// @param maxBalance_ Maximum balance of single user.
    event MaxBalanceSet(uint256 maxBalance_);

    /// @dev New `cap` value is set.
    /// @param cap_ Maximum total supply of the token.
    event CapSet(uint256 cap_);

    /// @dev Maximum balance of single user.
    function maxBalance() external view returns (uint256);

    /// @dev Maximum total supply of the token.
    function cap() external view returns (uint256);

    /// @dev Sets new maximum balance of a user.
    function setMaxBalance(uint256 newMaxBalance) external;

    /// @dev Sets new cap for the token.
    function setCap(uint256 newCap) external;

    /// @dev Mint wrapped token to cover any underlyingTokens that would have been transferred by mistake.
    /// @param account Addres to mint wrapped tokens to.
    function recover(address account) external returns (uint256);
}
