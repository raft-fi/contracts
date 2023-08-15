// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRToken } from "../Interfaces/IRToken.sol";
import { IPositionManager } from "../Interfaces/IPositionManager.sol";
import { IPSMFeeCalculator } from "./IPSMFeeCalculator.sol";

/// @dev Interface for Peg Stability Module of R.
/// Can be used to:
///   - mint R by depositing reserve token
///   - buy reserve token by burning R
interface IPSM is IERC20 {
    /// @dev Emitted when fee calculator contract address is set.
    /// @param newFeeCalculator Address of the new fee calculator.
    event FeeCalculatorSet(IPSMFeeCalculator newFeeCalculator);

    /// @dev Emitted when tokens are recovered from the contract.
    /// @param token The address of the token being recovered.
    /// @param to The address receiving the recovered tokens.
    /// @param amount The amount of tokens recovered.
    event TokensRecovered(IERC20 token, address to, uint256 amount);

    /// @dev Zero input was provided to various methods.
    error ZeroInputProvided();

    /// @dev Resulting swap ends up in returning less than minimum amount user provided.
    /// @param amount Actual amount of token to get in return.
    /// @param minReturn User provided minimum amount to get in return.
    error ReturnLessThanMinimum(uint256 amount, uint256 minReturn);

    /// @return Address of the R token.
    function rToken() external view returns (IRToken);

    /// @return Address of the reserve token.
    function reserveToken() external view returns (IERC20);

    /// @return Address of the Position manager contract responsible for minting R.
    function positionManager() external view returns (IPositionManager);

    /// @return Address of the fee calculator contract.
    function feeCalculator() external view returns (IPSMFeeCalculator);

    /// @dev Mint R by depositing reserve token to the contract.
    /// @param amount Amount of reserve token depositing.
    /// @param minReturn Minimum amount of R user wants to get in return.
    /// @return rAmountOut Actual amount of R token returned to user.
    /// @notice Amount of R minted is amount - fee.
    function buyR(uint256 amount, uint256 minReturn) external returns (uint256 rAmountOut);

    /// @dev Buys reserve token by burning R.
    /// @param amount Amount of R burning.
    /// @param minReturn Minimum amount of reserve token user wants to get in return.
    /// @return reserveAmountOut Actual amount of reserve token returned to user.
    /// @notice Amount of reserve token user will get is amount - fee.
    function buyReserveToken(uint256 amount, uint256 minReturn) external returns (uint256 reserveAmountOut);

    /// @dev Sets new fee calculator contract.
    /// @param newFeeCalculator Address of the new fee calculator contract.
    function setFeeCalculator(IPSMFeeCalculator newFeeCalculator) external;

    /// @dev Withdraws amount of reserve tokens to specified address.
    /// @param to Address to send reserve tokens to.
    /// @param amount Amount of tokens to send.
    /// @notice Should be used by governance to diversify protocol reserves.
    function withdrawReserve(address to, uint256 amount) external;

    /// @dev Recover accidentally sent tokens to the contract
    /// @param token Address of the token contract.
    /// @param to Address of the receiver of the tokens.
    /// @param amount Number of tokens to recover.
    /// @notice It can be used to withdraw yield bearing ERC20 if reserve is deposited to it.
    /// However, this is not an issue since we already allow withdrawing reserve via `withdrawReserve`.
    function recoverTokens(IERC20 token, address to, uint256 amount) external;
}
