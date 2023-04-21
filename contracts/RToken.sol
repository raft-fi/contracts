// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import { ERC20FlashMint, IERC3156FlashLender } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20FlashMint.sol";
import { PositionManagerDependent } from "./PositionManagerDependent.sol";
import { IRToken } from "./Interfaces/IRToken.sol";
import { FeeCollector } from "./FeeCollector.sol";

contract RToken is ERC20Permit, ERC20FlashMint, PositionManagerDependent, FeeCollector, IRToken {
    // --- Constants ---

    uint256 public constant override PERCENTAGE_BASE = 10_000;
    uint256 public constant override MAX_FLASH_MINT_FEE_PERCENTAGE = 500;

    // --- Variables ---

    uint256 public override flashMintFeePercentage;

    // --- Constructor ---

    /// @dev Deploys new R token. Sets flash mint fee percentage to 0. Transfers ownership to @param feeRecipient.
    /// @param positionManager Address of the PositionManager contract that is authorized to mint and burn new tokens.
    /// @param feeRecipient Address of flash mint fee recipient.
    constructor(
        address positionManager,
        address feeRecipient
    )
        ERC20Permit("R Stablecoin")
        ERC20("R Stablecoin", "R")
        PositionManagerDependent(positionManager)
        FeeCollector(feeRecipient)
    {
        flashMintFeePercentage = 0;

        transferOwnership(feeRecipient);

        emit RDeployed(positionManager, feeRecipient);
    }

    // --- Functions ---

    function mint(address to, uint256 amount) external override onlyPositionManager {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external override onlyPositionManager {
        _burn(from, amount);
    }

    function setFlashMintFeePercentage(uint256 feePercentage) public override onlyOwner {
        if (feePercentage > MAX_FLASH_MINT_FEE_PERCENTAGE) {
            revert FlashFeePercentageTooBig(feePercentage);
        }
        flashMintFeePercentage = feePercentage;
    }

    /// @dev Inherited from ERC20FlashMint. Defines maximum size of the flash mint.
    /// @param token Token to be flash minted. Returns 0 amount in case of token != address(this).
    function maxFlashLoan(address token)
        public
        view
        virtual
        override(ERC20FlashMint, IERC3156FlashLender)
        returns (uint256)
    {
        return token == address(this) ? Math.min(totalSupply() / 10, ERC20FlashMint.maxFlashLoan(address(this))) : 0;
    }

    /// @dev Inherited from ERC20FlashMint. Defines flash mint fee for the flash mint of @param amount tokens.
    /// @param token Token to be flash minted. Returns 0 fee in case of token != address(this).
    /// @param amount Size of the flash mint.
    function _flashFee(address token, uint256 amount) internal view virtual override returns (uint256) {
        return token == address(this) ? amount * flashMintFeePercentage / PERCENTAGE_BASE : 0;
    }

    /// @dev Inherited from ERC20FlashMint. Defines flash mint fee receiver.
    /// @return Address that will receive flash mint fees.
    function _flashFeeReceiver() internal view virtual override returns (address) {
        return feeRecipient;
    }
}
