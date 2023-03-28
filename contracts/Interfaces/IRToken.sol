// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";

error InvalidAddressInput();
error UnauthorizedCall(address caller);
error FlashFeePercentageTooBig(uint256 feePercentage);

interface IRToken is IERC20, IERC20Permit, IERC3156FlashLender {
    event RDeployed(address troveManager, address flashMintFeeRecipient);

    function PERCENTAGE_BASE() external view returns (uint256);

    function troveManager() external view returns (address);

    function mint(address _account, uint256 _amount) external;
    function burn(address _account, uint256 _amount) external;

    function returnFromPool(address poolAddress, address user, uint256 _amount ) external;

    function MAX_FLASH_MINT_FEE_PERCENTAGE() external view returns (uint256);
    function flashMintFeePercentage() external view returns (uint256);
    function setFlashMintFeePercentage(uint256 _feePercentage) external;
    function flashMintFeeRecipient() external view returns (address);
    function setFlashFeeRecipient(address _feeRecipient) external;
}
