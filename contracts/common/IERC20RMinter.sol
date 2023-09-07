// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRToken } from "../Interfaces/IRToken.sol";
import { IPositionManager } from "../Interfaces/IPositionManager.sol";

interface IRMinter {
    /// @dev Emitted when tokens are recovered from the contract.
    /// @param token The address of the token being recovered.
    /// @param to The address receiving the recovered tokens.
    /// @param amount The amount of tokens recovered.
    event TokensRecovered(IERC20 token, address to, uint256 amount);

    /// @return Address of the R token.
    function r() external view returns (IRToken);

    /// @return Address of the Position manager contract responsible for minting R.
    function positionManager() external view returns (IPositionManager);

    /// @dev Recover accidentally sent tokens to the contract
    /// @param token Address of the token contract.
    /// @param to Address of the receiver of the tokens.
    /// @param amount Number of tokens to recover.
    function recoverTokens(IERC20 token, address to, uint256 amount) external;
}
