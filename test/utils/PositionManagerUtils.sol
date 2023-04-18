// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Fixed256x18} from "@tempus-labs/contracts/math/Fixed256x18.sol";
import {MathUtils} from "../../contracts/Dependencies/MathUtils.sol";
import {IStEth} from "../../contracts/Dependencies/IStEth.sol";
import {IPositionManager} from "../../contracts/Interfaces/IPositionManager.sol";
import {IPositionManagerStEth} from "../../contracts/Interfaces/IPositionManagerStEth.sol";
import {StEthPositionManager} from "../../contracts/StEthPositionManager.sol";
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
        address upperHint,
        address lowerHint,
        uint256 icr,
        uint256 amount,
        ETHType ethType
    ) internal returns (OpenPositionResult memory result) {
        result.icr = icr;
        (result.debtAmount, result.totalDebt, amount) =
            getOpenPositionSetupValues(positionManager, priceFeed, extraDebtAmount, icr, amount);

        if (ethType == ETHType.ETH) {
            IStEth stEth = IPositionManagerStEth(address(positionManager)).stEth();
            uint256 wstEthAmount = stEth.getSharesByPooledEth(amount);
            IPositionManagerStEth(address(positionManager)).managePositionEth{value: amount}(
                result.debtAmount, true, upperHint, lowerHint, maxFeePercentage
            );
            result.collateral = wstEthAmount;
        } else if (ethType == ETHType.STETH) {
            IStEth stEth = IPositionManagerStEth(address(positionManager)).stEth();
            uint256 wstEthAmount = stEth.getSharesByPooledEth(amount);
            stEth.approve(address(positionManager), amount);
            IPositionManagerStEth(address(positionManager)).managePositionStEth(
                amount, true, result.debtAmount, true, upperHint, lowerHint, maxFeePercentage
            );
            result.collateral = wstEthAmount;
        } else {
            collateralToken.approve(address(positionManager), amount);
            positionManager.managePosition(
                collateralToken, amount, true, result.debtAmount, true, upperHint, lowerHint, maxFeePercentage
            );
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
            positionManager,
            priceFeed,
            collateralToken,
            MathUtils._100_PERCENT,
            0,
            address(0),
            address(0),
            icr,
            0,
            ETHType.WSTETH
        );
    }

    function openPositionStEth(
        IPositionManager positionManager,
        PriceFeedTestnet priceFeed,
        IERC20 collateralToken,
        uint256 icr,
        ETHType ethType
    ) internal returns (OpenPositionResult memory result) {
        result = openPosition(
            positionManager,
            priceFeed,
            collateralToken,
            MathUtils._100_PERCENT,
            0,
            address(0),
            address(0),
            icr,
            0,
            ethType
        );
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
            address(0),
            address(0),
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
            address(0),
            address(0),
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
        debtAmount = getNetBorrowingAmount(positionManager, positionManager.minDebt()) + extraDebtAmount;
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
        uint256 icr,
        address upperHint,
        address lowerHint
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

        positionManager.managePosition(
            _collateralToken, 0, false, result.debtAmount, true, upperHint, lowerHint, maxFeePercentage
        );
    }

    function withdrawDebt(
        IPositionManager positionManager,
        IERC20 collateralToken,
        PriceFeedTestnet priceFeed,
        address borrower,
        uint256 icr
    ) internal returns (WithdrawDebtResult memory result) {
        uint256 maxFee = MathUtils._100_PERCENT;
        result =
            withdrawDebt(positionManager, collateralToken, priceFeed, borrower, maxFee, 0, icr, address(0), address(0));
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
