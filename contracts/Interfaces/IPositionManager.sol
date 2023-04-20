// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Indexable} from "./IERC20Indexable.sol";
import {IFeeCollector} from "./IFeeCollector.sol";
import {IPriceFeed} from "./IPriceFeed.sol";
import {IRToken} from "./IRToken.sol";
import {ISplitLiquidationCollateral} from "./ISplitLiquidationCollateral.sol";

/// @dev Common interface for the Position Manager.
interface IPositionManager is IFeeCollector {
    // --- Errors ---

    /// @dev Max fee percentage must be between borrowing spread and 100%.
    error InvalidMaxFeePercentage();

    /// @dev Max fee percentage must be between 0.5% and 100%.
    error MaxFeePercentageOutOfRange();

    /// @dev Position is not active (either does not exist or closed).
    error PositionNotActive();

    /// @dev Requested redemption amount is > user's R token balance.
    error RedemptionAmountExceedsBalance();

    /// @dev Only one position in the system.
    error OnlyOnePositionInSystem();

    /// @dev Amount is zero.
    error AmountIsZero();

    /// @dev Nothing to liquidate.
    error NothingToLiquidate();

    /// @dev Unable to redeem any amount.
    error UnableToRedeemAnyAmount();

    /// @dev Fee would eat up all returned collateral.
    error FeeEatsUpAllReturnedCollateral();

    /// @dev Borrowing spread exceeds maximum.
    error BorrowingSpreadExceedsMaximum();

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

    /// @dev Fee exceeded provided maximum fee percentage
    error FeeExceedsMaxFee(uint256 fee, uint256 amount, uint256 maxFeePercentage);

    /// @dev Collateral token is not added.
    error CollateralTokenNotAdded();

    /// @dev Borrower has a different collateral token.
    error BorrowerHasDifferentCollateralToken();

    /// @dev Collateral token already added.
    error CollateralTokenAlreadyAdded();

    /// @dev Split liquidation collateral cannot be zero.
    error SplitLiquidationCollateralCannotBeZero();

    // --- Events ---

    /// @dev New position manager has been token deployed.
    /// @param rToken The R token used by the position manager.
    /// @param raftDebtToken The Raft indexable debt token.
    /// @param feeRecipient The address of fee recipient.
    event PositionManagerDeployed(IRToken rToken, IERC20Indexable raftDebtToken, address feeRecipient);

    /// @dev New collateral token has been added added to the system.
    /// @param collateralToken The token used as collateral.
    /// @param raftCollateralToken The Raft indexable collateral token for a given collateral token.
    /// @param priceFeed The contract that provides price for the collateral token.
    /// @param positionSize The maximum number of positions for a given collateral token.
    event CollateralTokenAdded(
        IERC20 collateralToken, IERC20Indexable raftCollateralToken, IPriceFeed priceFeed, uint256 positionSize
    );

    /// @dev Global delegate has been added to the whitelist or removed from it.
    /// @param delegate The address of the delegate that was whitelisted.
    /// @param isWhitelisted True if it is added to whitelist, false otherwise.
    event GlobalDelegateUpdated(address delegate, bool isWhitelisted);

    /// @dev New position has been created.
    /// @param position The address of the user opening new position.
    event PositionCreated(address indexed position);

    /// @dev The position has been closed by either repayment, liquidation, or redemption.
    /// @param position The address of the user whose position is closed.
    event PositionClosed(address indexed position);

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
    /// @param _attemptedAmount The amount of debt that was attempted to be redeemed.
    /// @param _actualAmount The amount of debt that was actually redeemed.
    /// @param _collateralSent The amount of collateral sent to the redeemer.
    /// @param _fee The amount of fee paid to the fee recipient.
    event Redemption(uint256 _attemptedAmount, uint256 _actualAmount, uint256 _collateralSent, uint256 _fee);

    /// @dev Borrowing spread has been updated.
    /// @param _borrowingSpread The new borrowing spread.
    event BorrowingSpreadUpdated(uint256 _borrowingSpread);

    /// @dev Redemption spread has been updated.
    /// @param redemptionSpread The new redemption spread.
    event RedemptionSpreadUpdated(uint256 redemptionSpread);

    /// @dev Base rate has been updated.
    /// @param _baseRate The new base rate.
    event BaseRateUpdated(uint256 _baseRate);

    /// @dev Last fee operation time has been updated.
    /// @param _lastFeeOpTime The new operation time.
    event LastFeeOpTimeUpdated(uint256 _lastFeeOpTime);

    /// @dev Split liquidation collateral has been changed changed.
    /// @param newSplitLiquidationCollateral New value that was set to be split liquidation collateral.
    event SplitLiquidationCollateralChanged(ISplitLiquidationCollateral indexed newSplitLiquidationCollateral);

    // --- Functions ---

    /// @return The R token used by position manager.
    function rToken() external view returns (IRToken);

    /// @return The Raft indexable debt token.
    function raftDebtToken() external view returns (IERC20Indexable);

    /// @dev Returns the Raft indexable collateral token for a given collateral token.
    /// @param _collateralToken The token used as collateral.
    /// @return raftCollateralToken The Raft indexable collateral token.
    function raftCollateralTokens(IERC20 _collateralToken)
        external
        view
        returns (IERC20Indexable raftCollateralToken);

    /// @dev Returns the collateral token that a given borrower used for their position.
    /// @param _borrower The address of the borrower.
    /// @return collateralToken The collateral token of the borrower's position.
    function collateralTokenForBorrower(address _borrower) external view returns (IERC20 collateralToken);

    /// @dev Returns the price feed for a given collateral token.
    /// @param _collateralToken The token used as collateral.
    /// @return priceFeed The contract that provides a price for the collateral token.
    function priceFeeds(IERC20 _collateralToken) external view returns (IPriceFeed priceFeed);

    /// @dev Returns address of the split liquidation collateral contract.
    function splitLiquidationCollateral() external view returns (ISplitLiquidationCollateral);

    /// @dev Sets the new split liquidation collateral contract.
    /// @param newSplitLiquidationCollateral New split liquidation collateral contract address.
    function setSplitLiquidationCollateral(ISplitLiquidationCollateral newSplitLiquidationCollateral) external;

    /// @return The max borrowing spread.
    function MAX_BORROWING_SPREAD() external view returns (uint256);

    /// @return The min redemption spread.
    function MIN_REDEMPTION_SPREAD() external view returns (uint256);

    /// @return The max redemption spread.
    function MAX_REDEMPTION_SPREAD() external view returns (uint256);

    /// @dev Adds global delegate to or removes it from the whitelist.
    /// @param delegate The address of the delegate that is being added or removed.
    /// @param isWhitelisted True if the delegate should be whitelisted, false for removing it.
    function setGlobalDelegateWhitelist(address delegate, bool isWhitelisted) external;

    /// @dev Returns if a given delegate is whitelisted globally.
    /// @param delegate The address of the delegate.
    /// @return isWhitelisted True if the delegate is whitelisted globally, false otherwise.
    function globalDelegateWhitelist(address delegate) external view returns (bool isWhitelisted);

    /// @dev Returns if a given delegate is whitelisted for a given borrower.
    /// @param borrower The address of the borrower.
    /// @param delegate The address of the delegate.
    /// @return isWhitelisted True if the delegate is whitelisted for a given borrower, false otherwise.
    function individualDelegateWhitelist(address borrower, address delegate)
        external
        view
        returns (bool isWhitelisted);

    /// @dev A doubly linked list of positions, sorted by by their collateral ratios.
    /// @param _collateralToken The token used as collateral.
    /// @return first The ID of the first position in the list.
    /// @return last The ID of the last position in the list.
    /// @return maxSize The maximum size of the list.
    /// @return size The current size of the list.
    function sortedPositions(IERC20 _collateralToken)
        external
        view
        returns (address first, address last, uint256 maxSize, uint256 size);

    /// @dev Adds a new collateral token to the protocol.
    /// @param _collateralToken The new collateral token.
    /// @param _priceFeed The price feed for the collateral token.
    /// @param _positionsSize The maximum size of the per-collateral-token list of positions.
    function addCollateralToken(IERC20 _collateralToken, IPriceFeed _priceFeed, uint256 _positionsSize) external;

    /// @dev Returns the position node for a given position ID.
    /// @param _collateralToken The token used as collateral.
    /// @param _id The ID of the position.
    /// @return exists True if the node exists, false otherwise.
    /// @return previousID The ID of the previous position in the list.
    /// @return nextID The ID of the next position in the list.
    function sortedPositionsNodes(IERC20 _collateralToken, address _id)
        external
        view
        returns (bool exists, address previousID, address nextID);

    /// @dev Returns the nominal individual collateral ratio for a given borrower.
    /// @param _collateralToken The token used as collateral.
    /// @param _borrower The address of the borrower.
    /// @return The nominal individual collateral ratio.
    function getNominalICR(IERC20 _collateralToken, address _borrower) external view returns (uint256);

    /// @dev Returns the current individual collateral ratio for a given borrower.
    /// @param _collateralToken The token used as collateral.
    /// @param _borrower The address of the borrower.
    /// @param _price The price of the collateral token.
    /// @return The current individual collateral ratio.
    function getCurrentICR(IERC20 _collateralToken, address _borrower, uint256 _price)
        external
        view
        returns (uint256);

    /// @dev Liquidates the borrower if its position's ICR is lower than the minimum collateral ratio.
    /// @param _collateralToken The token used as collateral.
    /// @param _borrower The address of the borrower.
    function liquidate(IERC20 _collateralToken, address _borrower) external;

    /// @dev Redeems the collateral token for a given debt amount. It sends @param debtAmount R to the system and
    /// redeems the corresponding amount of collateral from as many positions as are needed to fill the redemption
    /// request.
    /// @param _collateralToken The token used as collateral.
    /// @param debtAmount The amount of debt to be redeemed. Must be greater than zero.
    /// @param _firstRedemptionHint The first position ID to use as a hint for the search.
    /// @param _upperPartialRedemptionHint The upper partial redemption hint.
    /// @param _lowerPartialRedemptionHint The lower partial redemption hint.
    /// @param _partialRedemptionHintNICR The NICR of the partial redemption hint.
    /// @param _maxIterations The maximum number of iterations to use for the search. If zero, it will be ignored.
    /// @param _maxFee The maximum fee to pay for the redemption.
    function redeemCollateral(
        IERC20 _collateralToken,
        uint256 debtAmount,
        address _firstRedemptionHint,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint256 _partialRedemptionHintNICR,
        uint256 _maxIterations,
        uint256 _maxFee
    ) external;

    /// @return The current redemption spread.
    function redemptionSpread() external view returns (uint256);

    /// @dev Sets the new redemption spread.
    /// @param redemptionSpread_ New redemption spread to be used.
    function setRedemptionSpread(uint256 redemptionSpread_) external;

    /// @return The current redemption rate.
    function getRedemptionRate() external view returns (uint256);

    /// @return The current redemption rate with decay.
    function getRedemptionRateWithDecay() external view returns (uint256);

    /// @dev Returns the redemption fee with decay for a given collateral amount.
    /// @param _collateralAmount The amount of collateral.
    /// @return The redemption fee with decay.
    function getRedemptionFeeWithDecay(uint256 _collateralAmount) external view returns (uint256);

    /// @return The current borrowing spread.
    function borrowingSpread() external view returns (uint256);

    /// @dev Sets the new borrowing spread.
    /// @param _borrowingSpread New borrowing spread to be used.
    function setBorrowingSpread(uint256 _borrowingSpread) external;

    /// @return The current borrowing rate.
    function getBorrowingRate() external view returns (uint256);

    /// @return The current borrowing rate with decay.
    function getBorrowingRateWithDecay() external view returns (uint256);

    /// @dev Returns the borrowing fee for a given debt amount.
    /// @param debtAmount The amount of debt.
    /// @return The borrowing fee.
    function getBorrowingFee(uint256 debtAmount) external view returns (uint256);

    /// @dev Returns the borrowing fee with decay for a given debt amount.
    /// @param debtAmount The amount of debt.
    /// @return The borrowing fee with decay.
    function getBorrowingFeeWithDecay(uint256 debtAmount) external view returns (uint256);

    /// @dev Manages the position on behalf of a given borrower.
    /// @param _collateralToken The token the borrower used as collateral.
    /// @param _borrower The address of the borrower.
    /// @param _collateralChange The amount of collateral to add or remove.
    /// @param _isCollateralIncrease True if the collateral is being increased, false otherwise.
    /// @param _debtChange The amount of R to add or remove.
    /// @param _isDebtIncrease True if the debt is being increased, false otherwise.
    /// @param _upperHint The upper hint for the position ID.
    /// @param _lowerHint The lower hint for the position ID.
    /// @param _maxFeePercentage The maximum fee percentage to pay for the position management.
    function managePosition(
        IERC20 _collateralToken,
        address _borrower,
        uint256 _collateralChange,
        bool _isCollateralIncrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external;

    /// @dev Manages the position for the borrower (the caller).
    /// @param _collateralToken The token the borrower used as collateral.
    /// @param _collateralChange The amount of collateral to add or remove.
    /// @param _isCollateralIncrease True if the collateral is being increased, false otherwise.
    /// @param _debtChange The amount of R to add or remove.
    /// @param _isDebtIncrease True if the debt is being increased, false otherwise.
    /// @param _upperHint The upper hint for the position ID.
    /// @param _lowerHint The lower hint for the position ID.
    /// @param _maxFeePercentage The maximum fee percentage to pay for the position management.
    function managePosition(
        IERC20 _collateralToken,
        uint256 _collateralChange,
        bool _isCollateralIncrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external;

    /// @dev Whitelists a delegate.
    /// @param delegate The address of the delegate.
    function whitelistDelegate(address delegate) external;
}
