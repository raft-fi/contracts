// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../contracts/PositionManager.sol";
import "../../TestContracts/PriceFeedTestnet.sol";

library PositionManagerUtils {
    struct OpenPositionResult {
        uint256 rAmount;
        uint256 netDebt;
        uint256 totalDebt;
        uint256 icr;
        uint256 collateral;
    }

    function openPosition(
        IPositionManager positionManager,
        PriceFeedTestnet priceFeed,
        IERC20 collateralToken,
        uint256 maxFeePercentage,
        uint256 extraRAmount,
        address upperHint,
        address lowerHint,
        uint256 icr,
        uint256 amount
    ) internal returns (OpenPositionResult memory result) {
        uint256 minDebt = getNetBorrowingAmount(positionManager, MathUtils.MIN_NET_DEBT);
        result.rAmount = minDebt + extraRAmount;
        result.icr = icr;

        if (result.icr == 0 && amount == 0) {
            result.icr = 150 * MathUtils._100pct / 100;
        }

        result.totalDebt = getOpenPositionTotalDebt(positionManager, result.rAmount);
        result.netDebt = MathUtils.getNetDebt(result.totalDebt);

        if (result.icr > 0) {
            uint256 price = priceFeed.getPrice();
            amount = result.icr * result.totalDebt / price;
        }

        collateralToken.approve(address(positionManager), amount);
        positionManager.openPosition(maxFeePercentage, result.rAmount, upperHint, lowerHint, amount);

        result.collateral = amount;
    }

    function openPosition(
        IPositionManager positionManager,
        PriceFeedTestnet priceFeed,
        IERC20 collateralToken,
        uint256 icr
    ) internal returns (OpenPositionResult memory result) {
        result = openPosition(
            positionManager,
            priceFeed,
            collateralToken,
            MathUtils._100pct,
            0,
            address(0),
            address(0),
            icr,
            0
        );
    }

    function openPosition(
        IPositionManager positionManager,
        PriceFeedTestnet priceFeed,
        IERC20 collateralToken,
        uint256 extraRAmount,
        uint256 icr
    ) internal returns (OpenPositionResult memory result) {
        result = openPosition(
            positionManager,
            priceFeed,
            collateralToken,
            MathUtils._100pct,
            extraRAmount,
            address(0),
            address(0),
            icr,
            0
        );
    }

    function getNetBorrowingAmount(IPositionManager _positionManager, uint256 _debtWithFee) internal view returns (uint256) {
        uint256 borrowingRate = _positionManager.getBorrowingRateWithDecay();
        uint256 result = _debtWithFee * 1e18 / (1e18 + borrowingRate);

        if (borrowingRate % 1e18 == 0) {
            return result;
        }

        return result + 1;
    }

    function getOpenPositionTotalDebt(IPositionManager _positionManager, uint256 rAmount) internal view returns (uint256) {
        uint256 fee = _positionManager.getBorrowingFee(rAmount);
        return MathUtils.getCompositeDebt(rAmount) + fee;
    }
}
