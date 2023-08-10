// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IPositionManagerWithRedstoneOracle } from "./Interfaces/IPositionManagerWithRedstoneOracle.sol";
import { IRedstonePriceOracle } from "./Oracles/Interfaces/IRedstonePriceOracle.sol";
import {
    ERC20PermitSignature,
    PositionManagerWrappedCollateralToken,
    IERC20Wrapped
} from "./PositionManagerWrappedCollateralToken.sol";

contract PositionManagerWithRedstoneOracle is
    PositionManagerWrappedCollateralToken,
    IPositionManagerWithRedstoneOracle
{
    // --- Immutable variables ---

    IRedstonePriceOracle public immutable override redstonePriceOracle;

    // --- Constructor ---

    constructor(
        address positionManager_,
        IERC20Wrapped wrappedCollateralToken_,
        IRedstonePriceOracle redstonePriceOracle_
    )
        PositionManagerWrappedCollateralToken(positionManager_, wrappedCollateralToken_)
    {
        if (address(redstonePriceOracle_) == address(0)) {
            revert RedstonePriceOracleCannotBeZeroAddress();
        }
        redstonePriceOracle = redstonePriceOracle_;
    }

    // --- Functions ---

    function managePosition(
        uint256,
        bool,
        uint256,
        bool,
        uint256,
        ERC20PermitSignature calldata
    )
        public
        pure
        override
    {
        revert NotSupported();
    }

    function managePosition(
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        ERC20PermitSignature calldata permitSignature,
        bytes calldata redstonePayload
    )
        public
        override
    {
        redstonePriceOracle.setPrice(redstonePayload);
        super.managePosition(
            collateralChange, isCollateralIncrease, debtChange, isDebtIncrease, maxFeePercentage, permitSignature
        );
    }

    function redeemCollateral(uint256, uint256, ERC20PermitSignature calldata) public pure override {
        revert NotSupported();
    }

    function redeemCollateral(
        uint256 amount,
        uint256 maxFeePercentage,
        ERC20PermitSignature calldata permitSignature,
        bytes calldata redstonePayload
    )
        public
        override
    {
        redstonePriceOracle.setPrice(redstonePayload);
        super.redeemCollateral(amount, maxFeePercentage, permitSignature);
    }
}
