// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20FlashMint.sol";
import "./Interfaces/IRToken.sol";
import "./FeeCollector.sol";
import "./PositionManager.sol";
import "./PositionManagerDependent.sol";

contract RToken is ERC20Permit, ERC20FlashMint, PositionManagerDependent, FeeCollector, IRToken {
    uint256 public override flashMintFeePercentage;

    uint256 public constant override MAX_FLASH_MINT_FEE_PERCENTAGE = 500;
    uint256 public constant override PERCENTAGE_BASE = 10_000;

    constructor(IPositionManager _positionManager, address _feeRecipient)
        ERC20Permit("R Stablecoin")
        ERC20("R Stablecoin", "R")
        PositionManagerDependent(_positionManager)
        FeeCollector(_feeRecipient)
    {
        flashMintFeePercentage = 0;

        transferOwnership(_feeRecipient);

        emit RDeployed(_positionManager, _feeRecipient);
    }

    function mint(address _account, uint256 _amount) external override onlyPositionManager {
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external override onlyPositionManager {
        _burn(_account, _amount);
    }

    function maxFlashLoan(address token)
        public
        view
        virtual
        override(ERC20FlashMint, IERC3156FlashLender)
        returns (uint256)
    {
        return token == address(this) ? Math.min(totalSupply() / 10, ERC20FlashMint.maxFlashLoan(address(this))) : 0;
    }

    function _flashFee(address token, uint256 amount) internal view virtual override returns (uint256) {
        return token == address(this) ? amount * flashMintFeePercentage / PERCENTAGE_BASE : 0;
    }

    function setFlashMintFeePercentage(uint256 _feePercentage) public override onlyOwner {
        if (_feePercentage > MAX_FLASH_MINT_FEE_PERCENTAGE) {
            revert FlashFeePercentageTooBig(_feePercentage);
        }
        flashMintFeePercentage = _feePercentage;
    }
}
