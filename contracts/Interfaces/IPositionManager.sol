// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IERC20Indexable } from "./IERC20Indexable.sol";
import { IFeeCollector } from "./IFeeCollector.sol";
import { IPriceFeed } from "./IPriceFeed.sol";
import { IRToken } from "./IRToken.sol";
import { ISplitLiquidationCollateral } from "./ISplitLiquidationCollateral.sol";

/// @dev Common interface for the Position Manager.
interface IPositionManager is IFeeCollector {
    // --- Types ---

    /// @dev Information for a Raft indexable collateral token.
    /// @param collateralToken The Raft indexable collateral token.
    /// @param debtToken Coresponding Rafft indexable debt token.
    /// @param priceFeed The contract that provides a price for the collateral token.
    /// @param splitLiquidation The contract that calculates collateral split in case of liquidation.
    /// @param isEnabled Whether the token can be used as collateral or not.
    /// @param lastFeeOperationTime Timestamp of the last operation for the collateral token.
    /// @param borrowingSpread The current borrowing spread.
    /// @param baseRate The current base rate.
    /// @param redemptionSpread The current redemption spread.
    /// @param redemptionRebate Percentage of the redemption fee returned to redeemed positions.
    struct CollateralTokenInfo {
        IERC20Indexable collateralToken;
        IERC20Indexable debtToken;
        IPriceFeed priceFeed;
        ISplitLiquidationCollateral splitLiquidation;
        bool isEnabled;
        uint256 lastFeeOperationTime;
        uint256 borrowingSpread;
        uint256 baseRate;
        uint256 redemptionSpread;
        uint256 redemptionRebate;
    }

    // --- Events ---

    /// @dev New position manager has been token deployed.
    /// @param rToken The R token used by the position manager.
    /// @param feeRecipient The address of fee recipient.
    event PositionManagerDeployed(IRToken rToken, address feeRecipient);

    /// @dev New collateral token has been added added to the system.
    /// @param collateralToken The token used as collateral.
    /// @param raftCollateralToken The Raft indexable collateral token for the given collateral token.
    /// @param raftDebtToken The Raft indexable debt token for given collateral token.
    /// @param priceFeed The contract that provides price for the collateral token.
    event CollateralTokenAdded(
        IERC20 collateralToken,
        IERC20Indexable raftCollateralToken,
        IERC20Indexable raftDebtToken,
        IPriceFeed priceFeed
    );

    /// @dev Collateral token has been enabled or disabled.
    /// @param collateralToken The token used as collateral.
    /// @param isEnabled True if the token is enabled, false otherwise.
    event CollateralTokenModified(IERC20 collateralToken, bool isEnabled);

    /// @dev A delegate has been whitelisted for a certain position.
    /// @param position The position for which the delegate was whitelisted.
    /// @param delegate The delegate which was whitelisted.
    /// @param whitelisted Specifies whether the delegate whitelisting has been enabled (true) or disabled (false).
    event DelegateWhitelisted(address indexed position, address indexed delegate, bool whitelisted);

    /// @dev New position has been created.
    /// @param position The address of the user opening new position.
    /// @param collateralToken The token used as collateral for the created position.
    event PositionCreated(address indexed position, IERC20 indexed collateralToken);

    /// @dev The position has been closed by either repayment, liquidation, or redemption.
    /// @param position The address of the user whose position is closed.
    event PositionClosed(address indexed position);

    /// @dev Collateral amount for the position has been changed.
    /// @param position The address of the user that has opened the position.
    /// @param collateralToken The address of the collateral token being added to position.
    /// @param collateralAmount The amount of collateral added or removed.
    /// @param isCollateralIncrease Whether the collateral is added to the position or removed from it.
    event CollateralChanged(
        address indexed position, IERC20 indexed collateralToken, uint256 collateralAmount, bool isCollateralIncrease
    );

    /// @dev Debt amount for position has been changed.
    /// @param position The address of the user that has opened the position.
    /// @param collateralToken The address of the collateral token backing the debt.
    /// @param debtAmount The amount of debt added or removed.
    /// @param isDebtIncrease Whether the debt is added to the position or removed from it.
    event DebtChanged(
        address indexed position, IERC20 indexed collateralToken, uint256 debtAmount, bool isDebtIncrease
    );

    /// @dev Borrowing fee has been paid. Emitted only if the actual fee was paid - doesn't happen with no fees are
    /// paid.
    /// @param collateralToken Collateral token used to mint R.
    /// @param position The address of position's owner that triggered the fee payment.
    /// @param feeAmount The amount of tokens paid as the borrowing fee.
    event RBorrowingFeePaid(IERC20 collateralToken, address indexed position, uint256 feeAmount);

    /// @dev Liquidation has been executed.
    /// @param liquidator The liquidator that executed the liquidation.
    /// @param position The address of position's owner whose position was liquidated.
    /// @param collateralToken The collateral token used for the liquidation.
    /// @param debtLiquidated The total debt that was liquidated or redistributed.
    /// @param collateralLiquidated The total collateral liquidated.
    /// @param collateralSentToLiquidator The collateral amount sent to the liquidator.
    /// @param collateralLiquidationFeePaid The total collateral paid as the liquidation fee to the fee recipient.
    /// @param isRedistribution Whether the executed liquidation was redistribution or not.
    event Liquidation(
        address indexed liquidator,
        address indexed position,
        IERC20 indexed collateralToken,
        uint256 debtLiquidated,
        uint256 collateralLiquidated,
        uint256 collateralSentToLiquidator,
        uint256 collateralLiquidationFeePaid,
        bool isRedistribution
    );

    /// @dev Redemption has been executed.
    /// @param redeemer User that redeemed R.
    /// @param amount Amount of R that was redeemed.
    /// @param collateralSent The amount of collateral sent to the redeemer.
    /// @param fee The amount of fee paid to the fee recipient.
    /// @param rebate Redemption rebate amount.
    event Redemption(address indexed redeemer, uint256 amount, uint256 collateralSent, uint256 fee, uint256 rebate);

    /// @dev Borrowing spread has been updated.
    /// @param borrowingSpread The new borrowing spread.
    event BorrowingSpreadUpdated(uint256 borrowingSpread);

    /// @dev Redemption rebate has been updated.
    /// @param redemptionRebate The new redemption rebate.
    event RedemptionRebateUpdated(uint256 redemptionRebate);

    /// @dev Redemption spread has been updated.
    /// @param collateralToken Collateral token that the spread was set for.
    /// @param redemptionSpread The new redemption spread.
    event RedemptionSpreadUpdated(IERC20 collateralToken, uint256 redemptionSpread);

    /// @dev Base rate has been updated.
    /// @param collateralToken Collateral token that the baser rate was updated for.
    /// @param baseRate The new base rate.
    event BaseRateUpdated(IERC20 collateralToken, uint256 baseRate);

    /// @dev Last fee operation time has been updated.
    /// @param collateralToken Collateral token that the baser rate was updated for.
    /// @param lastFeeOpTime The new operation time.
    event LastFeeOpTimeUpdated(IERC20 collateralToken, uint256 lastFeeOpTime);

    /// @dev Split liquidation collateral has been changed.
    /// @param collateralToken Collateral token whose split liquidation collateral contract is set.
    /// @param newSplitLiquidationCollateral New value that was set to be split liquidation collateral.
    event SplitLiquidationCollateralChanged(
        IERC20 collateralToken, ISplitLiquidationCollateral indexed newSplitLiquidationCollateral
    );

    // --- Errors ---

    /// @dev Max fee percentage must be between borrowing spread and 100%.
    error InvalidMaxFeePercentage();

    /// @dev Max fee percentage must be between 0.5% and 100%.
    error MaxFeePercentageOutOfRange();

    /// @dev Amount is zero.
    error AmountIsZero();

    /// @dev Nothing to liquidate.
    error NothingToLiquidate();

    /// @dev Cannot liquidate last position.
    error CannotLiquidateLastPosition();

    /// @dev Cannot redeem collateral below minimum debt threshold.
    /// @param collateralToken Collateral token used to redeem.
    /// @param newTotalDebt New total debt backed by collateral, which is lower than minimum debt.
    error TotalDebtCannotBeLowerThanMinDebt(IERC20 collateralToken, uint256 newTotalDebt);

    /// @dev Cannot redeem collateral
    /// @param collateralToken Collateral token used to redeem.
    /// @param newTotalCollateral New total collateral, which is lower than minimum collateral.
    /// @param minimumCollateral Minimum collateral required to complete redeem
    error TotalCollateralCannotBeLowerThanMinCollateral(
        IERC20 collateralToken, uint256 newTotalCollateral, uint256 minimumCollateral
    );

    /// @dev Fee would eat up all returned collateral.
    error FeeEatsUpAllReturnedCollateral();

    /// @dev Borrowing spread exceeds maximum.
    error BorrowingSpreadExceedsMaximum();

    /// @dev Redemption rebate exceeds maximum.
    error RedemptionRebateExceedsMaximum();

    /// @dev Redemption spread is out of allowed range.
    error RedemptionSpreadOutOfRange();

    /// @dev There must be either a collateral change or a debt change.
    error NoCollateralOrDebtChange();

    /// @dev There is some collateral for position that doesn't have debt.
    error InvalidPosition();

    /// @dev An operation that would result in ICR < MCR is not permitted.
    /// @param newICR Resulting ICR that is bellow MCR.
    error NewICRLowerThanMCR(uint256 newICR);

    /// @dev Position's net debt must be greater than minimum.
    /// @param netDebt Net debt amount that is below minimum.
    error NetDebtBelowMinimum(uint256 netDebt);

    /// @dev The provided delegate address is invalid.
    error InvalidDelegateAddress();

    /// @dev A non-whitelisted delegate cannot adjust positions.
    error DelegateNotWhitelisted();

    /// @dev Fee exceeded provided maximum fee percentage.
    /// @param fee The fee amount.
    /// @param amount The amount of debt or collateral.
    /// @param maxFeePercentage The maximum fee percentage.
    error FeeExceedsMaxFee(uint256 fee, uint256 amount, uint256 maxFeePercentage);

    /// @dev Borrower uses a different collateral token already.
    error PositionCollateralTokenMismatch();

    /// @dev Collateral token address cannot be zero.
    error CollateralTokenAddressCannotBeZero();

    /// @dev Price feed address cannot be zero.
    error PriceFeedAddressCannotBeZero();

    /// @dev Collateral token already added.
    error CollateralTokenAlreadyAdded();

    /// @dev Collateral token is not added.
    error CollateralTokenNotAdded();

    /// @dev Collateral token is not enabled.
    error CollateralTokenDisabled();

    /// @dev Split liquidation collateral cannot be zero.
    error SplitLiquidationCollateralCannotBeZero();

    /// @dev Cannot change collateral in case of repaying the whole debt.
    error WrongCollateralParamsForFullRepayment();

    // --- Functions ---

    /// @return The R token used by position manager.
    function rToken() external view returns (IRToken);

    /// @dev Retrieves information about certain collateral type.
    /// @param collateralToken The token used as collateral.
    /// @return raftCollateralToken The Raft indexable collateral token.
    /// @return raftDebtToken The Raft indexable debt token.
    /// @return priceFeed The contract that provides a price for the collateral token.
    /// @return splitLiquidation The contract that calculates collateral split in case of liquidation.
    /// @return isEnabled Whether the collateral token can be used as collateral or not.
    /// @return lastFeeOperationTime Timestamp of the last operation for the collateral token.
    /// @return borrowingSpread The current borrowing spread.
    /// @return baseRate The current base rate.
    /// @return redemptionSpread The current redemption spread.
    /// @return redemptionRebate Percentage of the redemption fee returned to redeemed positions.
    function collateralInfo(IERC20 collateralToken)
        external
        view
        returns (
            IERC20Indexable raftCollateralToken,
            IERC20Indexable raftDebtToken,
            IPriceFeed priceFeed,
            ISplitLiquidationCollateral splitLiquidation,
            bool isEnabled,
            uint256 lastFeeOperationTime,
            uint256 borrowingSpread,
            uint256 baseRate,
            uint256 redemptionSpread,
            uint256 redemptionRebate
        );

    /// @param collateralToken Collateral token whose raft collateral indexable token is being queried.
    /// @return Raft collateral token address for given collateral token.
    function raftCollateralToken(IERC20 collateralToken) external view returns (IERC20Indexable);

    /// @param collateralToken Collateral token whose raft collateral indexable token is being queried.
    /// @return Raft debt token address for given collateral token.
    function raftDebtToken(IERC20 collateralToken) external view returns (IERC20Indexable);

    /// @param collateralToken Collateral token whose price feed contract is being queried.
    /// @return Price feed contract address for given collateral token.
    function priceFeed(IERC20 collateralToken) external view returns (IPriceFeed);

    /// @param collateralToken Collateral token whose split liquidation collateral is being queried.
    /// @return Returns address of the split liquidation collateral contract.
    function splitLiquidationCollateral(IERC20 collateralToken) external view returns (ISplitLiquidationCollateral);

    /// @param collateralToken Collateral token whose split liquidation collateral is being queried.
    /// @return Returns whether collateral is enabled or nor.
    function collateralEnabled(IERC20 collateralToken) external view returns (bool);

    /// @param collateralToken Collateral token we query last operation time fee for.
    /// @return The timestamp of the latest fee operation (redemption or new R issuance).
    function lastFeeOperationTime(IERC20 collateralToken) external view returns (uint256);

    /// @param collateralToken Collateral token we query borrowing spread for.
    /// @return The current borrowing spread.
    function borrowingSpread(IERC20 collateralToken) external view returns (uint256);

    /// @param collateralToken Collateral token we query base rate for.
    /// @return rate The base rate.
    function baseRate(IERC20 collateralToken) external view returns (uint256 rate);

    /// @param collateralToken Collateral token we query redemption spread for.
    /// @return The current redemption spread for collateral token.
    function redemptionSpread(IERC20 collateralToken) external view returns (uint256);

    /// @param collateralToken Collateral token we query redemption rebate for.
    /// @return rebate Percentage of the redemption fee returned to redeemed positions.
    function redemptionRebate(IERC20 collateralToken) external view returns (uint256);

    /// @param collateralToken Collateral token we query redemption rate for.
    /// @return rate The current redemption rate for collateral token.
    function getRedemptionRate(IERC20 collateralToken) external view returns (uint256 rate);

    /// @dev Returns the collateral token that a given position used for their position.
    /// @param position The address of the borrower.
    /// @return collateralToken The collateral token of the borrower's position.
    function collateralTokenForPosition(address position) external view returns (IERC20 collateralToken);

    /// @dev Adds a new collateral token to the protocol.
    /// @param collateralToken The new collateral token.
    /// @param priceFeed The price feed for the collateral token.
    /// @param newSplitLiquidationCollateral split liquidation collateral contract address.
    function addCollateralToken(
        IERC20 collateralToken,
        IPriceFeed priceFeed,
        ISplitLiquidationCollateral newSplitLiquidationCollateral
    )
        external;

    /// @dev Enables or disables a collateral token. Reverts if the collateral token has not been added.
    /// @param collateralToken The collateral token.
    /// @param isEnabled Whether the collateral token can be used as collateral or not.
    function setCollateralEnabled(IERC20 collateralToken, bool isEnabled) external;

    /// @dev Sets the new split liquidation collateral contract.
    /// @param collateralToken Collateral token whose split liquidation collateral is being set.
    /// @param newSplitLiquidationCollateral New split liquidation collateral contract address.
    function setSplitLiquidationCollateral(
        IERC20 collateralToken,
        ISplitLiquidationCollateral newSplitLiquidationCollateral
    )
        external;

    /// @dev Liquidates the borrower if its position's ICR is lower than the minimum collateral ratio.
    /// @param position The address of the borrower.
    function liquidate(address position) external;

    /// @dev Redeems the collateral token for a given debt amount. It sends @param debtAmount R to the system and
    /// redeems the corresponding amount of collateral from as many positions as are needed to fill the redemption
    /// request.
    /// @param collateralToken The token used as collateral.
    /// @param debtAmount The amount of debt to be redeemed. Must be greater than zero.
    /// @param maxFeePercentage The maximum fee percentage to pay for the redemption.
    function redeemCollateral(IERC20 collateralToken, uint256 debtAmount, uint256 maxFeePercentage) external;

    /// @dev Manages the position on behalf of a given borrower.
    /// @param collateralToken The token the borrower used as collateral.
    /// @param position The address of the borrower.
    /// @param collateralChange The amount of collateral to add or remove.
    /// @param isCollateralIncrease True if the collateral is being increased, false otherwise.
    /// @param debtChange The amount of R to add or remove. In case of repayment (isDebtIncrease = false)
    /// `type(uint256).max` value can be used to repay the whole outstanding loan.
    /// @param isDebtIncrease True if the debt is being increased, false otherwise.
    /// @param maxFeePercentage The maximum fee percentage to pay for the position management.
    /// @param permitSignature Optional permit signature for tokens that support IERC20Permit interface.
    /// @notice `permitSignature` it is ignored if permit signature is not for `collateralToken`.
    /// @notice In case of full debt repayment, `isCollateralIncrease` is ignored and `collateralChange` must be 0.
    /// These values are set to `false`(collateral decrease), and the whole collateral balance of the user.
    /// @return actualCollateralChange Actual amount of collateral added/removed.
    /// Can be different to `collateralChange` in case of full repayment.
    /// @return actualDebtChange Actual amount of debt added/removed.
    /// Can be different to `debtChange` in case of passing type(uint256).max as `debtChange`.
    function managePosition(
        IERC20 collateralToken,
        address position,
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        ERC20PermitSignature calldata permitSignature
    )
        external
        returns (uint256 actualCollateralChange, uint256 actualDebtChange);

    /// @return The max borrowing spread.
    function MAX_BORROWING_SPREAD() external view returns (uint256);

    /// @return The max borrowing rate.
    function MAX_BORROWING_RATE() external view returns (uint256);

    /// @dev Sets the new borrowing spread.
    /// @param collateralToken Collateral token we set borrowing spread for.
    /// @param newBorrowingSpread New borrowing spread to be used.
    function setBorrowingSpread(IERC20 collateralToken, uint256 newBorrowingSpread) external;

    /// @param collateralToken Collateral token we query borrowing rate for.
    /// @return The current borrowing rate.
    function getBorrowingRate(IERC20 collateralToken) external view returns (uint256);

    /// @param collateralToken Collateral token we query borrowing rate with decay for.
    /// @return The current borrowing rate with decay.
    function getBorrowingRateWithDecay(IERC20 collateralToken) external view returns (uint256);

    /// @dev Returns the borrowing fee for a given debt amount.
    /// @param collateralToken Collateral token we query borrowing fee for.
    /// @param debtAmount The amount of debt.
    /// @return The borrowing fee.
    function getBorrowingFee(IERC20 collateralToken, uint256 debtAmount) external view returns (uint256);

    /// @dev Sets the new redemption spread.
    /// @param newRedemptionSpread New redemption spread to be used.
    function setRedemptionSpread(IERC20 collateralToken, uint256 newRedemptionSpread) external;

    /// @dev Sets new redemption rebate percentage.
    /// @param newRedemptionRebate Value that is being set as a redemption rebate percentage.
    function setRedemptionRebate(IERC20 collateralToken, uint256 newRedemptionRebate) external;

    /// @param collateralToken Collateral token we query redemption rate with decay for.
    /// @return The current redemption rate with decay.
    function getRedemptionRateWithDecay(IERC20 collateralToken) external view returns (uint256);

    /// @dev Returns the redemption fee for a given collateral amount.
    /// @param collateralToken Collateral token we query redemption fee for.
    /// @param collateralAmount The amount of collateral.
    /// @param priceDeviation Deviation for the reported price by oracle in percentage.
    /// @return The redemption fee.
    function getRedemptionFee(
        IERC20 collateralToken,
        uint256 collateralAmount,
        uint256 priceDeviation
    )
        external
        view
        returns (uint256);

    /// @dev Returns the redemption fee with decay for a given collateral amount.
    /// @param collateralToken Collateral token we query redemption fee with decay for.
    /// @param collateralAmount The amount of collateral.
    /// @return The redemption fee with decay.
    function getRedemptionFeeWithDecay(
        IERC20 collateralToken,
        uint256 collateralAmount
    )
        external
        view
        returns (uint256);

    /// @return Half-life of 12h (720 min).
    /// @dev (1/2) = d^720 => d = (1/2)^(1/720)
    function MINUTE_DECAY_FACTOR() external view returns (uint256);

    /// @dev Returns if a given delegate is whitelisted for a given borrower.
    /// @param position The address of the borrower.
    /// @param delegate The address of the delegate.
    /// @return isWhitelisted True if the delegate is whitelisted for a given borrower, false otherwise.
    function isDelegateWhitelisted(address position, address delegate) external view returns (bool isWhitelisted);

    /// @dev Whitelists a delegate.
    /// @param delegate The address of the delegate.
    /// @param whitelisted True if delegate is being whitelisted, false otherwise.
    function whitelistDelegate(address delegate, bool whitelisted) external;

    /// @return Parameter by which to divide the redeemed fraction, in order to calc the new base rate from a
    /// redemption. Corresponds to (1 / ALPHA) in the white paper.
    function BETA() external view returns (uint256);
}
