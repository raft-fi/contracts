// SPDX-License-Identifier: MIT
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
    /// @param token The Raft indexable collateral token.
    /// @param isEnabled Whether the token can be used as collateral or not.
    struct RaftCollateralTokenInfo {
        IERC20Indexable token;
        bool isEnabled;
    }

    // --- Events ---

    /// @dev New position manager has been token deployed.
    /// @param rToken The R token used by the position manager.
    /// @param raftDebtToken The Raft indexable debt token.
    /// @param feeRecipient The address of fee recipient.
    event PositionManagerDeployed(IRToken rToken, IERC20Indexable raftDebtToken, address feeRecipient);

    /// @dev New collateral token has been added added to the system.
    /// @param collateralToken The token used as collateral.
    /// @param raftCollateralToken The Raft indexable collateral token for the given collateral token.
    /// @param priceFeed The contract that provides price for the collateral token.
    event CollateralTokenAdded(IERC20 collateralToken, IERC20Indexable raftCollateralToken, IPriceFeed priceFeed);

    /// @dev Collateral token has been enabled or disabled.
    /// @param collateralToken The token used as collateral.
    /// @param raftCollateralToken The Raft indexable collateral token for the given collateral token.
    /// @param isEnabled True if the token is enabled, false otherwise.
    event CollateralTokenModified(IERC20 collateralToken, IERC20Indexable raftCollateralToken, bool isEnabled);

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
    /// @param collateralToken The token used as collateral for the closed position.
    event PositionClosed(address indexed position, IERC20 indexed collateralToken);

    /// @dev Collateral amount for the position has been changed.
    /// @param position The address of the user that has opened the position.
    /// @param collateralAmount The amount of collateral added or removed.
    /// @param isCollateralIncrease Whether the collateral is added to the position or removed from it.
    event CollateralChanged(address indexed position, uint256 collateralAmount, bool isCollateralIncrease);

    /// @dev Debt amount for position has been changed.
    /// @param position The address of the user that has opened the position.
    /// @param debtAmount The amount of debt added or removed.
    /// @param isDebtIncrease Whether the debt is added to the position or removed from it.
    event DebtChanged(address indexed position, uint256 debtAmount, bool isDebtIncrease);

    /// @dev Total debt in the system has been changed.
    /// @param totalDebt The new total debt in the system.
    event TotalDebtChanged(uint256 totalDebt);

    /// @dev Borrowing fee has been paid. Emitted only if the actual fee was paid - doesn't happen with no fees are
    /// paid.
    /// @param position The address of position's owner that triggered the fee payment.
    /// @param feeAmount The amount of tokens paid as the borrowing fee.
    event RBorrowingFeePaid(address indexed position, uint256 feeAmount);

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
    /// @param redemptionSpread The new redemption spread.
    event RedemptionSpreadUpdated(uint256 redemptionSpread);

    /// @dev Base rate has been updated.
    /// @param baseRate The new base rate.
    event BaseRateUpdated(uint256 baseRate);

    /// @dev Last fee operation time has been updated.
    /// @param lastFeeOpTime The new operation time.
    event LastFeeOpTimeUpdated(uint256 lastFeeOpTime);

    /// @dev Split liquidation collateral has been changed.
    /// @param newSplitLiquidationCollateral New value that was set to be split liquidation collateral.
    event SplitLiquidationCollateralChanged(ISplitLiquidationCollateral indexed newSplitLiquidationCollateral);

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

    // --- Functions ---

    /// @return The R token used by position manager.
    function rToken() external view returns (IRToken);

    /// @return The Raft indexable debt token.
    function raftDebtToken() external view returns (IERC20Indexable);

    /// @dev Returns the Raft indexable collateral token for a given collateral token.
    /// @param collateralToken The token used as collateral.
    /// @return raftCollateralToken The Raft indexable collateral token.
    /// @return isEnabled Whether the collateral token can be used as collateral or not.
    function raftCollateralTokens(IERC20 collateralToken)
        external
        view
        returns (IERC20Indexable raftCollateralToken, bool isEnabled);

    /// @dev Returns the collateral token that a given position used for their position.
    /// @param position The address of the borrower.
    /// @return collateralToken The collateral token of the borrower's position.
    function collateralTokenForPosition(address position) external view returns (IERC20 collateralToken);

    /// @dev Adds a new collateral token to the protocol.
    /// @param collateralToken The new collateral token.
    /// @param priceFeed The price feed for the collateral token.
    function addCollateralToken(IERC20 collateralToken, IPriceFeed priceFeed) external;

    /// @dev Enables or disables a collateral token. Reverts if the collateral token has not been added.
    /// @param collateralToken The collateral token.
    /// @param isEnabled Whether the collateral token can be used as collateral or not.
    function modifyCollateralToken(IERC20 collateralToken, bool isEnabled) external;

    /// @dev Returns the price feed for a given collateral token.
    /// @param collateralToken The token used as collateral.
    /// @return priceFeed The contract that provides a price for the collateral token.
    function priceFeeds(IERC20 collateralToken) external view returns (IPriceFeed priceFeed);

    /// @dev Returns address of the split liquidation collateral contract.
    function splitLiquidationCollateral() external view returns (ISplitLiquidationCollateral);

    /// @dev Sets the new split liquidation collateral contract.
    /// @param newSplitLiquidationCollateral New split liquidation collateral contract address.
    function setSplitLiquidationCollateral(ISplitLiquidationCollateral newSplitLiquidationCollateral) external;

    /// @dev Liquidates the borrower if its position's ICR is lower than the minimum collateral ratio.
    /// @param collateralToken The token used as collateral.
    /// @param position The address of the borrower.
    function liquidate(IERC20 collateralToken, address position) external;

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
    /// @notice 'permitSignature' it is ignored if permit signature is not for 'collateralToken'.
    /// @notice In case of full debt repayment, `isCollateralIncrease` and `collateralChange` are ignored.
    /// These values are set to `false`(collateral decrease), and the whole collateral balance of the user.
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
        external;

    /// @return The max borrowing spread.
    function MAX_BORROWING_SPREAD() external view returns (uint256);

    /// @return The max borrowing rate.
    function MAX_BORROWING_RATE() external view returns (uint256);

    /// @return The current borrowing spread.
    function borrowingSpread() external view returns (uint256);

    /// @dev Sets the new borrowing spread.
    /// @param newBorrowingSpread New borrowing spread to be used.
    function setBorrowingSpread(uint256 newBorrowingSpread) external;

    /// @return The current borrowing rate.
    function getBorrowingRate() external view returns (uint256);

    /// @return The current borrowing rate with decay.
    function getBorrowingRateWithDecay() external view returns (uint256);

    /// @dev Returns the borrowing fee for a given debt amount.
    /// @param debtAmount The amount of debt.
    /// @return The borrowing fee.
    function getBorrowingFee(uint256 debtAmount) external view returns (uint256);

    /// @return The min redemption spread.
    function MIN_REDEMPTION_SPREAD() external view returns (uint256);

    /// @return The max redemption spread.
    function MAX_REDEMPTION_SPREAD() external view returns (uint256);

    /// @return The current redemption spread.
    function redemptionSpread() external view returns (uint256);

    /// @return The base rate.
    function baseRate() external view returns (uint256);

    /// @dev Sets the new redemption spread.
    /// @param newRedemptionSpread New redemption spread to be used.
    function setRedemptionSpread(uint256 newRedemptionSpread) external;

    /// @return The current redemption rate.
    function getRedemptionRate() external view returns (uint256);

    /// @return Percentage of the redemption fee returned to redeemed positions.
    function redemptionRebate() external view returns (uint256);

    /// @dev Sets new redemption rebate percentage.
    /// @param newRedemptionRebate Value that is being set as a redemption rebate percentage.
    function setRedemptionRebate(uint256 newRedemptionRebate) external;

    /// @return The current redemption rate with decay.
    function getRedemptionRateWithDecay() external view returns (uint256);

    /// @dev Returns the redemption fee for a given collateral amount.
    /// @param collateralAmount The amount of collateral.
    /// @param priceDeviation Deviation for the reported price by oracle in percentage.
    /// @return The redemption fee.
    function getRedemptionFee(uint256 collateralAmount, uint256 priceDeviation) external view returns (uint256);

    /// @dev Returns the redemption fee with decay for a given collateral amount.
    /// @param collateralAmount The amount of collateral.
    /// @return The redemption fee with decay.
    function getRedemptionFeeWithDecay(uint256 collateralAmount) external view returns (uint256);

    /// @return Half-life of 12h (720 min).
    /// @dev (1/2) = d^720 => d = (1/2)^(1/720)
    function MINUTE_DECAY_FACTOR() external view returns (uint256);

    /// @return The timestamp of the latest fee operation (redemption or new R issuance).
    function lastFeeOperationTime() external view returns (uint256);

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
