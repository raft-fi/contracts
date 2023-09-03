// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC3156FlashLender } from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPSM } from "./IPSM.sol";
import { IPSMFeeCalculator } from "./IPSMFeeCalculator.sol";

interface IUpperPegArbitrager {
    // --- Events ---

    /// @dev Emitted when tokens are rescued from the contract.
    /// @param token The address of the token being rescued.
    /// @param to The address receiving the rescued tokens.
    /// @param amount The amount of tokens rescued.
    event TokensRescued(IERC20 token, address to, uint256 amount);

    /// @dev Emitted when tokens are flash borrowed.
    /// @param token The address of the token being flash borrowed.
    /// @param amount The amount of tokens flash borrowed.
    /// @param fee The fee paid for the flash loan.
    event FlashBorrowed(IERC20 token, uint256 amount, uint256 fee);

    // --- Errors ---

    /// @dev Error when zero address is provided as input.
    error ZeroInputProvided();

    /// @dev Error when the caller is not the flash lender.
    /// @param lender The lender of the flash loan.
    error UntrustedLender(address lender);

    /// @dev Error when the caller is not the loan initiator.
    /// @param caller The caller of the flash loan.
    error UntrustedLoanInitiator(address caller);

    /// @dev Insufficient balance after flash loan.
    error InsufficientBalanceAfterFlashLoan();

    /// @dev Error when the action is not supported.
    error ActionNotSupported();

    // --- Functions ---

    /// @dev Returns the address of the flash lender.
    function lender() external view returns (IERC3156FlashLender);

    /// @dev Returns the address of the token being flash borrowed.
    function borrowToken() external view returns (IERC20);

    /// @dev Returns the address of the PSM.
    function psm() external view returns (IPSM);

    /// @dev Returns the address of the PSM fee calculator.
    function feeCalculator() external view returns (IPSMFeeCalculator);

    /// @param amount The amount of tokens to be flash borrowed.
    /// @param data The data to be passed to the `_executeSwap` function for OneInch swap.
    function flashBorrow(uint256 amount, bytes calldata data) external;

    /// @dev Recovers tokens that have been accidentally sent to the contract.
    /// @param token The address of the token to be recovered.
    /// @param to The address to which the rescued tokens should be sent.
    function rescueTokens(IERC20 token, address to) external;
}
