// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISplitLiquidationCollateral {
    // --- Functions ---

    /// @dev Splits collateral between protocol and liquidator.
    /// @param collateral Amount of collateral to split.
    /// @param debt Amount of debt to split.
    /// @param price Price of collateral.
    /// @param isRedistribution True if this is a redistribution.
    /// @param liquidationProtocolFee Protocol fee for liquidation.
    /// @return collateralToSendToProtocol Amount of collateral to send to protocol.
    /// @return collateralToSentToLiquidator Amount of collateral to send to liquidator.
    function split(
        uint256 collateral,
        uint256 debt,
        uint256 price,
        bool isRedistribution,
        uint256 liquidationProtocolFee
    ) external pure returns (uint256 collateralToSendToProtocol, uint256 collateralToSentToLiquidator);
}
