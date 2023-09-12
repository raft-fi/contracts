// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRToken } from "../Interfaces/IRToken.sol";
import { IPriceFeed } from "../Interfaces/IPriceFeed.sol";
import { IInterestRatePositionManager } from "./IInterestRatePositionManager.sol";
import { IPositionManager, PositionManager } from "../PositionManager.sol";
import { ERC20RMinter } from "../common/ERC20RMinter.sol";
import { ISplitLiquidationCollateral } from "../Interfaces/ISplitLiquidationCollateral.sol";

/// @dev Implementation of Position Manager. Current implementation does not support rebasing tokens as collateral.
contract InterestRatePositionManager is ERC20RMinter, PositionManager, IInterestRatePositionManager {
    // --- Errors ---

    error Unsupported();

    // --- Constructor ---

    /// @dev Initializes the position manager.
    constructor(IRToken rToken_)
        PositionManager(address(rToken_))
        ERC20RMinter(rToken_, "Interest Rate Posman", "IRPM")
    { }

    // --- External functions ---

    function mintFees(IERC20 collateralToken, uint256 amount) external {
        if (msg.sender != address(collateralInfo[collateralToken].debtToken)) {
            revert InvalidDebtToken(msg.sender);
        }
        _mintR(feeRecipient, amount);

        emit MintedFees(collateralToken, amount);
    }

    function redeemCollateral(IERC20, uint256, uint256) public virtual override(IPositionManager, PositionManager) {
        revert Unsupported();
    }

    function addCollateralToken(
        IERC20,
        IPriceFeed,
        ISplitLiquidationCollateral
    )
        public
        override(IPositionManager, PositionManager)
    {
        revert Unsupported();
    }

    // --- Helper functions ---

    function _mintRTokens(address to, uint256 amount) internal virtual override {
        _mintR(to, amount);
    }

    function _burnRTokens(address from, uint256 amount) internal virtual override {
        _burnR(from, amount);
    }

    function _triggerBorrowingFee(
        IERC20,
        address,
        uint256,
        uint256
    )
        internal
        pure
        virtual
        override
        returns (uint256)
    {
        return 0;
    }
}
