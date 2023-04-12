// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import { IFeeCollector } from "./IFeeCollector.sol";
import { IPositionManagerDependent } from "./IPositionManagerDependent.sol";

/// @dev Proposed flash mint fee percentage is too big.
/// @param feePercentage Proposed flash mint fee percentage.
error FlashFeePercentageTooBig(uint256 feePercentage);

/// @dev Interface of R stablecoin token. Implements some standards like IERC20, IERC20Permit, and IERC3156FlashLender.
/// Raft's specific implementation contains IFeeCollector and IPositionManagerDependent.
/// PositionManager can mint and burn R when particular actions happen with user's position.
interface IRToken is IERC20, IERC20Permit, IERC3156FlashLender, IFeeCollector, IPositionManagerDependent {
    /// @dev New R token is deployed
    /// @param positionManager Address of the PositionManager contract that is authorized to mint and burn new tokens.
    /// @param flashMintFeeRecipient Address of flash mint fee recipient.
    event RDeployed(address positionManager, address flashMintFeeRecipient);

    /// @return Number representing 100 percentage.
    function PERCENTAGE_BASE() external view returns (uint256);

    /// @dev Mints new tokens. Callable only by PositionManager contract.
    /// @param to Address that will receive newly minted tokens.
    /// @param amount Amount of tokens to mint.
    function mint(address to, uint256 amount) external;

    /// @dev Mints new tokens. Callable only by PositionManager contract.
    /// @param from Address of user whose tokens are burnt.
    /// @param amount Amount of tokens to burn.
    function burn(address from, uint256 amount) external;

    /// @return Maximum flash mint fee percentage that can be set by owner.
    function MAX_FLASH_MINT_FEE_PERCENTAGE() external view returns (uint256);

    /// @return Current flash mint fee percentage.
    function flashMintFeePercentage() external view returns (uint256);

    /// @dev Sets new flash mint fee percentage. Callable only by owner.
    /// @notice The proposed flash mint fee percentage cannot exceed `MAX_FLASH_MINT_FEE_PERCENTAGE`.
    /// @param feePercentage New flash fee percentage.
    function setFlashMintFeePercentage(uint256 feePercentage) external;
}
