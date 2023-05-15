// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { MathUtils } from "../../contracts/Dependencies/MathUtils.sol";
import { IStETH } from "../../contracts/Dependencies/IStETH.sol";
import { IERC20Indexable } from "../../contracts/Interfaces/IERC20Indexable.sol";
import { IPositionManager } from "../../contracts/Interfaces/IPositionManager.sol";
import { PositionManagerStETH } from "../../contracts/PositionManagerStETH.sol";
import { PriceFeedTestnet } from "../mocks/PriceFeedTestnet.sol";

library PositionManagerUtils {
    using Fixed256x18 for uint256;

    enum ETHType {
        ETH,
        STETH
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
        address position,
        uint256 maxFeePercentage,
        uint256 extraDebtAmount,
        uint256 icr,
        uint256 amount
    )
        internal
        returns (OpenPositionResult memory result)
    {
        result.icr = icr;
        (result.debtAmount, result.totalDebt, amount) =
            getOpenPositionSetupValues(positionManager, priceFeed, extraDebtAmount, icr, amount);

        collateralToken.approve(address(positionManager), amount);
        ERC20PermitSignature memory emptySignature;
        positionManager.managePosition(
            collateralToken, position, amount, true, result.debtAmount, true, maxFeePercentage, emptySignature
        );
        result.collateral = amount;
    }

    function openPosition(
        IPositionManager positionManager,
        PriceFeedTestnet priceFeed,
        IERC20 collateralToken,
        address position,
        uint256 icr
    )
        internal
        returns (OpenPositionResult memory result)
    {
        result = openPosition(positionManager, priceFeed, collateralToken, position, MathUtils._100_PERCENT, 0, icr, 0);
    }

    function openPositionStETH(
        PositionManagerStETH positionManagerStETH,
        PriceFeedTestnet priceFeed,
        uint256 icr,
        ETHType ethType,
        uint256 extraDebt
    )
        internal
        returns (OpenPositionResult memory result)
    {
        result.icr = icr;
        uint256 amount;
        (result.debtAmount, result.totalDebt, amount) = getOpenPositionSetupValues(
            IPositionManager(positionManagerStETH.positionManager()), priceFeed, extraDebt, icr, 0
        );
        ERC20PermitSignature memory emptySignature;

        if (ethType == ETHType.ETH) {
            IStETH stETH = positionManagerStETH.stETH();
            uint256 wstETHAmount = stETH.getSharesByPooledEth(amount);
            positionManagerStETH.managePositionETH{ value: amount }(
                result.debtAmount, true, MathUtils._100_PERCENT, emptySignature
            );
            result.collateral = wstETHAmount;
        } else {
            IStETH stETH = positionManagerStETH.stETH();
            uint256 wstETHAmount = stETH.getSharesByPooledEth(amount);
            stETH.approve(address(positionManagerStETH), amount);
            positionManagerStETH.managePositionStETH(
                amount, true, result.debtAmount, true, MathUtils._100_PERCENT, emptySignature
            );
            result.collateral = wstETHAmount;
        }

        return result;
    }

    function openPosition(
        IPositionManager positionManager,
        PriceFeedTestnet priceFeed,
        IERC20 collateralToken,
        address position,
        uint256 extraDebtAmount,
        uint256 icr
    )
        internal
        returns (OpenPositionResult memory result)
    {
        result = openPosition(
            positionManager, priceFeed, collateralToken, position, MathUtils._100_PERCENT, extraDebtAmount, icr, 0
        );
    }

    function openPosition(
        IPositionManager positionManager,
        PriceFeedTestnet priceFeed,
        IERC20 collateralToken,
        address position,
        uint256 extraDebtAmount,
        uint256 icr,
        uint256 amount
    )
        internal
        returns (OpenPositionResult memory result)
    {
        result = openPosition(
            positionManager, priceFeed, collateralToken, position, MathUtils._100_PERCENT, extraDebtAmount, icr, amount
        );
    }

    function getOpenPositionSetupValues(
        IPositionManager positionManager,
        PriceFeedTestnet priceFeed,
        uint256 extraDebtAmount,
        uint256 icr,
        uint256 amount
    )
        internal
        view
        returns (uint256 debtAmount, uint256 totalDebt, uint256 newAmount)
    {
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
        address position,
        uint256 maxFeePercentage,
        uint256 debtAmount,
        uint256 icr
    )
        internal
        returns (WithdrawDebtResult memory result)
    {
        // solhint-disable reason-string
        require(
            !(debtAmount > 0 && icr > 0) && (debtAmount > 0 || icr > 0),
            "Specify either R amount or target ICR, but not both"
        );
        // solhint-enable reason-string

        result.debtAmount = debtAmount;

        if (icr > 0) {
            IERC20 raftDebtToken = positionManager.raftDebtToken();
            (IERC20Indexable raftCollateralToken,,) = positionManager.raftCollateralTokens(_collateralToken);
            uint256 debt = raftDebtToken.balanceOf(position);
            uint256 collateral = raftCollateralToken.balanceOf(position);
            uint256 price = priceFeed.getPrice();
            uint256 targetDebt = collateral * price / icr;
            // solhint-disable-next-line reason-string
            require(targetDebt > debt, "Target debt is not greater than current debt");
            result.increasedTotalDebt = targetDebt - debt;
            result.debtAmount = getNetBorrowingAmount(positionManager, result.increasedTotalDebt);
        } else {
            result.increasedTotalDebt = getAmountWithBorrowingFee(positionManager, result.debtAmount);
        }

        ERC20PermitSignature memory emptySignature;
        positionManager.managePosition(
            _collateralToken, position, 0, false, result.debtAmount, true, maxFeePercentage, emptySignature
        );
    }

    function withdrawDebt(
        IPositionManager positionManager,
        IERC20 collateralToken,
        PriceFeedTestnet priceFeed,
        address position,
        uint256 icr
    )
        internal
        returns (WithdrawDebtResult memory result)
    {
        uint256 maxFee = MathUtils._100_PERCENT;
        result = withdrawDebt(positionManager, collateralToken, priceFeed, position, maxFee, 0, icr);
    }

    function getNetBorrowingAmount(
        IPositionManager _positionManager,
        uint256 _debtWithFee
    )
        internal
        view
        returns (uint256)
    {
        uint256 borrowingRate = _positionManager.getBorrowingRateWithDecay();
        return _debtWithFee.divUp(MathUtils._100_PERCENT + borrowingRate);
    }

    function getAmountWithBorrowingFee(
        IPositionManager positionManager,
        uint256 debtAmount
    )
        internal
        view
        returns (uint256)
    {
        return debtAmount + positionManager.getBorrowingFee(debtAmount);
    }

    function getCurrentICR(
        IPositionManager positionManager,
        IERC20 collateralToken,
        address position,
        uint256 price
    )
        public
        view
        returns (uint256)
    {
        (IERC20Indexable raftCollateralToken,,) = positionManager.raftCollateralTokens(collateralToken);
        return MathUtils._computeCR(
            raftCollateralToken.balanceOf(position), positionManager.raftDebtToken().balanceOf(position), price
        );
    }
}
