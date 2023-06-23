// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface ISplitLiquidationCollateral {
    // --- Functions ---

    /// @dev Returns lowest total debt that will be split.
    function LOW_TOTAL_DEBT() external view returns (uint256);

    /// @dev Minimum collateralization ratio for position
    function MCR() external view returns (uint256);

    /// @dev Splits collateral between protocol and liquidator.
    /// @param totalCollateral Amount of collateral to split.
    /// @param totalDebt Amount of debt to split.
    /// @param price Price of collateral.
    /// @param isRedistribution True if this is a redistribution.
    /// @return collateralToSendToProtocol Amount of collateral to send to protocol.
    /// @return collateralToSentToLiquidator Amount of collateral to send to liquidator.
    function split(
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 price,
        bool isRedistribution
    )
        external
        view
        returns (uint256 collateralToSendToProtocol, uint256 collateralToSentToLiquidator);
}
