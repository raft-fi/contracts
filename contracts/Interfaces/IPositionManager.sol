// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRToken} from "./IRToken.sol";
import {IERC20Indexable} from "./IERC20Indexable.sol";
import {IFeeCollector} from "./IFeeCollector.sol";
import {IPriceFeed} from "./IPriceFeed.sol";

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

    /// @dev Position array must is empty.
    error PositionArrayEmpty();

    /// @dev Fee would eat up all returned collateral.
    error FeeEatsUpAllReturnedCollateral();

    /// @dev Borrowing spread exceeds maximum.
    error BorrowingSpreadExceedsMaximum();

    /// @dev Trying to withdraw more collateral than what user has available.
    error WithdrawingMoreThanAvailableCollateral();

    /// @dev Cannot withdraw and add collateral at the same time.
    error NotSingularCollateralChange();

    /// @dev There must be either a collateral change or a debt change.
    error NoCollateralOrDebtChange();

    /// @dev An operation that would result in ICR < MCR is not permitted.
    /// @param newICR Resulting ICR that is bellow MCR.
    error NewICRLowerThanMCR(uint256 newICR);

    /// @dev Position's net debt must be greater than minimum.
    /// @param netDebt Net debt amount that is below minimum.
    error NetDebtBelowMinimum(uint256 netDebt);

    /// @dev Min debt value cannot be zero.
    error MinNetDebtCannotBeZero();

    /// @dev The provided Liquidation Protocol Fee is out of the allowed bound.
    error LiquidationProtocolFeeOutOfBound();

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

    // --- Events ---

    /// @dev New PositionManager contract is deployed.
    /// @param rToken Address of the rToken used by position manager.
    /// @param raftDebtToken Address of Raft indexable debt token.
    /// @param feeRecipient Fee recipient address.
    event PositionManagerDeployed(IRToken rToken, IERC20Indexable raftDebtToken, address feeRecipient);

    /// @dev New collateral token is added to the system.
    /// @param collateralToken Address of the token used as collateral.
    /// @param raftCollateralToken Address of Raft indexable collateral token.
    /// @param priceFeed Address of the contract that provides price for collateral token.
    /// @param positionSize Position size for the doubly linked list.
    event CollateralTokenAdded(
        IERC20 collateralToken, IERC20Indexable raftCollateralToken, IPriceFeed priceFeed, uint256 positionSize
    );

    /// @dev New position is created in Raft.
    /// @param position Address of the user opening new position.
    event PositionCreated(address indexed position);

    /// @dev Position is closed by repayment, liquidation, or redemption.
    /// @param position Address of user whose position is closed.
    event PositionClosed(address indexed position);

    /// @dev Collateral amount for position is changed.
    /// @param position Address of user that opened position.
    /// @param collateralAmount Amount of collateral added or removed.
    /// @param isCollateralIncrease Is collateral added to position or removed from it.
    event CollateralChanged(address indexed position, uint256 collateralAmount, bool isCollateralIncrease);

    /// @dev Debt amount for position is changed.
    /// @param position Address of user that opened position.
    /// @param debtAmount Amount of debt added or removed.
    /// @param isDebtIncrease Is debt added to position or removed from it.
    event DebtChanged(address indexed position, uint256 debtAmount, bool isDebtIncrease);

    /// @dev Borrowing fee is paid. Emitted only if actual fee was paid, doesn't happen with no fees paid.
    /// @param position Address of position owner that triggered fee payment.
    /// @param feeAmount Amount of tokens paid as borrowing fee.
    event RBorrowingFeePaid(address indexed position, uint256 feeAmount);

    /// @dev Liquidation was executed.
    /// @param liquidator Liquidator that executed liquidation.
    /// @param position Position that was liquidated.
    /// @param collateralToken Collateral token used for liquidation.
    /// @param debtLiquidated Total debt that was liquidated or redistributed.
    /// @param collateralLiquidated Total collateral liquidated.
    /// @param collateralSentToLiquidator Collateral amount sent to liquidator.
    /// @param collateralLiquidationFeePaid Total collateral paid as liquidation fee to the protocol.
    /// @param isRedistribution If executed liquidation was redistribution.
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

    /// @dev Minimum debt is changed.
    /// @param newMinDebt New value that was set to be minimum debt.
    event MinDebtChanged(uint256 newMinDebt);

    event LiquidationProtocolFeeChanged(uint256 _liquidationProtocolFee);
    event Redemption(uint256 _attemptedAmount, uint256 _actualAmount, uint256 _collateralSent, uint256 _fee);

    event BorrowingSpreadUpdated(uint256 _borrowingSpread);
    event BaseRateUpdated(uint256 _baseRate);
    event LastFeeOpTimeUpdated(uint256 _lastFeeOpTime);

    // --- Functions ---

    /// @dev Returns address of the rToken used by position manager.
    /// @return Address of the rToken used by position manager.
    function rToken() external view returns (IRToken);

    function raftDebtToken() external view returns (IERC20Indexable);

    /// @dev Return Raft indexable collateral token for the given collateral token.
    /// @param _collateralToken Address of the token used as collateral.
    /// @return raftCollateralToken Address of Raft indexable collateral token.
    function raftCollateralTokens(IERC20 _collateralToken)
        external
        view
        returns (IERC20Indexable raftCollateralToken);

    /// @dev Return price feed for the given collateral token.
    /// @param _collateralToken Address of the token used as collateral.
    /// @return priceFeed Address of the contract that provides price for collateral token.
    function priceFeeds(IERC20 _collateralToken) external view returns (IPriceFeed priceFeed);

    /// @dev Return collateral token per borrower.
    /// @param _borrower Address of the borrower.
    /// @return collateralToken Address of collateral token.
    function collateralTokenPerBorrowers(address _borrower) external view returns (IERC20 collateralToken);

    /// @return Minimum debt for open positions
    function minDebt() external view returns (uint256);

    /// @dev Sets the new min debt. Reverts if it is zero.
    /// @param newMinDebt New minimum debt to be used.
    function setMinDebt(uint256 newMinDebt) external;

    function liquidationProtocolFee() external view returns (uint256);
    function MAX_BORROWING_SPREAD() external view returns (uint256);
    function MAX_LIQUIDATION_PROTOCOL_FEE() external view returns (uint256);

    function globalDelegateWhitelist(address delegate) external view returns (bool isWhitelisted);
    function individualDelegateWhitelist(address borrower, address delegate)
        external
        view
        returns (bool isWhitelisted);

    /// @dev A doubly linked list of Positions, sorted by their sorted by their collateral ratios.
    /// @param _collateralToken Address of the token used as collateral.
    function sortedPositions(IERC20 _collateralToken)
        external
        view
        returns (address first, address last, uint256 maxSize, uint256 size);

    /// @dev Adds new collateral token to the system.
    /// @param _collateralToken Address of the token used as collateral.
    /// @param _priceFeed Address of the price feed for the collateral token.
    /// @param _positionsSize Max size of the per-collateral doubly linked list of positions.
    function addCollateralToken(IERC20 _collateralToken, IPriceFeed _priceFeed, uint256 _positionsSize) external;

    function setLiquidationProtocolFee(uint256 _liquidationProtocolFee) external;

    function sortedPositionsNodes(IERC20 _collateralToken, address _id)
        external
        view
        returns (bool exists, address nextId, address prevId);

    function getNominalICR(IERC20 _collateralToken, address _borrower) external view returns (uint256);
    function getCurrentICR(IERC20 _collateralToken, address _borrower, uint256 _price)
        external
        view
        returns (uint256);

    function liquidate(IERC20 _collateralToken, address _borrower) external;

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

    function getRedemptionRate() external view returns (uint256);
    function getRedemptionRateWithDecay() external view returns (uint256);

    function getRedemptionFeeWithDecay(uint256 _collateralTokenDrawn) external view returns (uint256);

    function borrowingSpread() external view returns (uint256);
    function setBorrowingSpread(uint256 _borrowingSpread) external;

    function getBorrowingRate() external view returns (uint256);
    function getBorrowingRateWithDecay() external view returns (uint256);

    function getBorrowingFee(uint256 rDebt) external view returns (uint256);
    function getBorrowingFeeWithDecay(uint256 _rDebt) external view returns (uint256);

    function managePosition(
        IERC20 _collateralToken,
        address _borrower,
        uint256 _collateralChange,
        bool _isCollateralIncrease,
        uint256 _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external;

    function managePosition(
        IERC20 _collateralToken,
        uint256 _collateralChange,
        bool _isCollateralIncrease,
        uint256 _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external;

    function whitelistDelegate(address delegate) external;
}
