// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManagerDependent} from "./IPositionManagerDependent.sol";

interface IERC20Indexable is IERC20, IPositionManagerDependent {
    // --- Events ---

    /// @dev New token is deployed.
    /// @param positionManager Address of the PositionManager contract that is authorized to mint and burn new tokens.
    event ERC20IndexableDeployed(address positionManager);

    // --- Errors ---

    /// @dev Unsupported action for ERC20Indexable contract.
    error NotSupported();

    // --- Functions ---

    /// @return Precision for token index. Represents index that is equal to 1.
    function INDEX_PRECISION() external view returns (uint256);

    /// @return Current index value.
    function currentIndex() external view returns (uint256);

    /// @dev Sets new token index. Callable only by PositionManager contract.
    /// @param backingAmount Amount of backing token that is covered by total supply.
    function setIndex(uint256 backingAmount) external;

    /// @dev Mints new tokens. Callable only by PositionManager contract.
    /// @param to Address that will receive newly minted tokens.
    /// @param amount Amount of tokens to mint.
    function mint(address to, uint256 amount) external;

    /// @dev Mints new tokens. Callable only by PositionManager contract.
    /// @param from Address of user whose tokens are burnt.
    /// @param amount Amount of tokens to burn.
    function burn(address from, uint256 amount) external;
}
