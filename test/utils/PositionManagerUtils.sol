// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Fixed256x18} from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import {MathUtils} from "../../contracts/Dependencies/MathUtils.sol";
import {IStETH} from "../../contracts/Dependencies/IStETH.sol";
import {IPositionManager} from "../../contracts/Interfaces/IPositionManager.sol";
import {IPositionManagerStETH} from "../../contracts/Interfaces/IPositionManagerStETH.sol";
import {PositionManagerStETH} from "../../contracts/PositionManagerStETH.sol";
import {PriceFeedTestnet} from "../TestContracts/PriceFeedTestnet.sol";

library PositionManagerUtils {
    using Fixed256x18 for uint256;

    enum ETHType {
        ETH,
        STETH,
        WSTETH
    }

    struct OpenPositionResult {
        uint256 debtAmount;
        uint256 totalDebt;
        uint256 icr;
        uint256 collateral;
    }

    struct WithdrawDebtResult {
        uint256 debtAmount;
        uint256 increasedTotalDebt;
    }

    function openPosition(
        IPositionManager positionManager,
        PriceFeedTestnet priceFeed,
        IERC20 collateralToken,
        uint256 maxFeePercentage,
        uint256 extraDebtAmount,
        uint256 icr,
        uint256 amount,
        ETHType ethType
    ) internal returns (OpenPositionResult memory result) {
        result.icr = icr;
        (result.debtAmount, result.totalDebt, amount) =
            getOpenPositionSetupValues(positionManager, priceFeed, extraDebtAmount, icr, amount);

        if (ethType == ETHType.ETH) {
            IStETH stETH = IPositionManagerStETH(address(positionManager)).stETH();
            uint256 wstETHAmount = stETH.getSharesByPooledEth(amount);
            IPositionManagerStETH(address(positionManager)).managePositionETH{value: amount}(
                result.debtAmount, true, maxFeePercentage
            );
            result.collateral = wstETHAmount;
        } else if (ethType == ETHType.STETH) {
            IStETH stETH = IPositionManagerStETH(address(positionManager)).stETH();
            uint256 wstETHAmount = stETH.getSharesByPooledEth(amount);
            stETH.approve(address(positionManager), amount);
            IPositionManagerStETH(address(positionManager)).managePositionStETH(
                amount, true, result.debtAmount, true, maxFeePercentage
            );
            result.collateral = wstETHAmount;
        } else {
            collateralToken.approve(address(positionManager), amount);
            positionManager.managePosition(collateralToken, amount, true, result.debtAmount, true, maxFeePercentage);
            result.collateral = amount;
        }
    }

    function openPosition(
        IPositionManager positionManager,
        PriceFeedTestnet priceFeed,
        IERC20 collateralToken,
        uint256 icr
    ) internal returns (OpenPositionResult memory result) {
        result = openPosition(
            positionManager, priceFeed, collateralToken, MathUtils._100_PERCENT, 0, icr, 0, ETHType.WSTETH
        );
    }

    function openPositionStETH(
        IPositionManager positionManager,
        PriceFeedTestnet priceFeed,
        IERC20 collateralToken,
        uint256 icr,
        ETHType ethType
    ) internal returns (OpenPositionResult memory result) {
        result = openPosition(positionManager, priceFeed, collateralToken, MathUtils._100_PERCENT, 0, icr, 0, ethType);
    }

    function openPosition(
        IPositionManager positionManager,
        PriceFeedTestnet priceFeed,
        IERC20 collateralToken,
        uint256 extraDebtAmount,
        uint256 icr
    ) internal returns (OpenPositionResult memory result) {
        result = openPosition(
            positionManager,
            priceFeed,
            collateralToken,
            MathUtils._100_PERCENT,
            extraDebtAmount,
            icr,
            0,
            ETHType.WSTETH
        );
    }

    function openPosition(
        IPositionManager positionManager,
        PriceFeedTestnet priceFeed,
        IERC20 collateralToken,
        uint256 extraDebtAmount,
        uint256 icr,
        uint256 amount
    ) internal returns (OpenPositionResult memory result) {
        result = openPosition(
            positionManager,
            priceFeed,
            collateralToken,
            MathUtils._100_PERCENT,
            extraDebtAmount,
            icr,
            amount,
            ETHType.WSTETH
        );
    }

    function getOpenPositionSetupValues(
        IPositionManager positionManager,
        PriceFeedTestnet priceFeed,
        uint256 extraDebtAmount,
        uint256 icr,
        uint256 amount
    ) internal view returns (uint256 debtAmount, uint256 totalDebt, uint256 newAmount) {
        debtAmount = getNetBorrowingAmount(
            positionManager, positionManager.splitLiquidationCollateral().LOW_TOTAL_DEBT()
        ) + extraDebtAmount;
        totalDebt = getAmountWithBorrowingFee(positionManager, debtAmount);
        newAmount = (amount == 0) ? icr * totalDebt / priceFeed.getPrice() : amount;
    }

    function withdrawDebt(
        IPositionManager positionManager,
        IERC20 _collateralToken,
        PriceFeedTestnet priceFeed,
        address borrower,
        uint256 maxFeePercentage,
        uint256 debtAmount,
        uint256 icr
    ) internal returns (WithdrawDebtResult memory result) {
        // solhint-disable reason-string
        require(
            !(debtAmount > 0 && icr > 0) && (debtAmount > 0 || icr > 0),
            "Specify either R amount or target ICR, but not both"
        );
        // solhint-enable reason-string

        result.debtAmount = debtAmount;

        if (icr > 0) {
            IERC20 raftDebtToken = positionManager.raftDebtToken();
            IERC20 raftCollateralToken = positionManager.raftCollateralTokens(_collateralToken);
            uint256 debt = raftDebtToken.balanceOf(borrower);
            uint256 collateral = raftCollateralToken.balanceOf(borrower);
            uint256 price = priceFeed.getPrice();
            uint256 targetDebt = collateral * price / icr;
            // solhint-disable-next-line reason-string
            require(targetDebt > debt, "Target debt is not greater than current debt");
            result.increasedTotalDebt = targetDebt - debt;
            result.debtAmount = getNetBorrowingAmount(positionManager, result.increasedTotalDebt);
        } else {
            result.increasedTotalDebt = getAmountWithBorrowingFee(positionManager, result.debtAmount);
        }

        positionManager.managePosition(_collateralToken, 0, false, result.debtAmount, true, maxFeePercentage);
    }

    function withdrawDebt(
        IPositionManager positionManager,
        IERC20 collateralToken,
        PriceFeedTestnet priceFeed,
        address borrower,
        uint256 icr
    ) internal returns (WithdrawDebtResult memory result) {
        uint256 maxFee = MathUtils._100_PERCENT;
        result = withdrawDebt(positionManager, collateralToken, priceFeed, borrower, maxFee, 0, icr);
    }

    function getNetBorrowingAmount(IPositionManager _positionManager, uint256 _debtWithFee)
        internal
        view
        returns (uint256)
    {
        uint256 borrowingRate = _positionManager.getBorrowingRateWithDecay();
        return _debtWithFee.divUp(MathUtils._100_PERCENT + borrowingRate);
    }

    function getAmountWithBorrowingFee(IPositionManager positionManager, uint256 debtAmount)
        internal
        view
        returns (uint256)
    {
        return debtAmount + positionManager.getBorrowingFee(debtAmount);
    }
}
