// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20FlashMint.sol";
import "./Interfaces/IRToken.sol";

/*
* Functionality on top of regular OZ implementation
* - returnFromPool(): functions callable only by Raft core contracts, which move R tokens between Raft <-> user.
*/

contract RToken is Ownable2Step, ERC20Permit, ERC20FlashMint, IRToken {
    // --- Addresses ---
    address public immutable override troveManager;
    address public immutable override borrowerOperations;
    address public override flashMintFeeRecipient;

    uint256 public override flashMintFeePercentage;

    uint256 public constant override MAX_FLASH_MINT_FEE_PERCENTAGE = 500;
    uint256 public constant override PERCENTAGE_BASE = 10_000;

    constructor(
        address _troveManager, 
        address _borrowerOperations
    ) ERC20Permit("R Stablecoin") ERC20("R Stablecoin", "R") {
        if (_troveManager == address(0) &&  _borrowerOperations == address(0)) {
            revert InvalidAddressInput();
        }

        troveManager = _troveManager;
        borrowerOperations = _borrowerOperations;
        flashMintFeeRecipient = msg.sender;
        flashMintFeePercentage = 0;

        emit RDeployed(_borrowerOperations, _troveManager, msg.sender);
    }

    function mint(address _account, uint256 _amount) external override {
        if (msg.sender != borrowerOperations) {
            revert UnauthorizedCall(msg.sender);
        }
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external override {
        if (msg.sender != borrowerOperations && msg.sender != troveManager) {
            revert UnauthorizedCall(msg.sender);
        }
        _burn(_account, _amount);
    }

    function returnFromPool(address _poolAddress, address _receiver, uint256 _amount) external override {
        if(msg.sender != troveManager) {
            revert UnauthorizedCall(msg.sender);
        }
        _transfer(_poolAddress, _receiver, _amount);
    }

    function maxFlashLoan(
        address token
    ) public view virtual override(ERC20FlashMint, IERC3156FlashLender) returns (uint256) {
        return token == address(this) ? Math.min(totalSupply() / 10, ERC20FlashMint.maxFlashLoan(address(this))) : 0;
    }

    function setFlashFeeRecipient(address _feeRecipient) public override onlyOwner {
        if (_feeRecipient == address(0)) {
            revert InvalidAddressInput();
        }
        flashMintFeeRecipient = _feeRecipient;
    }

    function _flashFeeReceiver() internal view virtual override returns (address) {
        return flashMintFeeRecipient;
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
