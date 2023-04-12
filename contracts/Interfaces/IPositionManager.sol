// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRToken} from "./IRToken.sol";
import {IERC20Indexable} from "./IERC20Indexable.sol";
import {IFeeCollector} from "./IFeeCollector.sol";
import {IPriceFeed} from "./IPriceFeed.sol";

/// @dev Max fee percentage must be between borrowing spread and 100%.
error PositionManagerInvalidMaxFeePercentage();

/// @dev Max fee percentage must be between 0.5% and 100%.
error PositionManagerMaxFeePercentageOutOfRange();

/// @dev Position is not active (either does not exist or closed).
error PositionManagerPositionNotActive();

/// @dev Requested redemption amount is > user's R token balance.
error PositionManagerRedemptionAmountExceedsBalance();

/// @dev Only one position in the system.
error PositionManagerOnlyOnePositionInSystem();

/// @dev Amount is zero.
error PositionManagerAmountIsZero();

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

/// @dev The provided Liquidation Protocol Fee is out of the allowed bound.
error LiquidationProtocolFeeOutOfBound();

/// @dev The provided delegate address is invalid.
error InvalidDelegateAddress();

/// @dev A non-whitelisted delegate cannot adjust positions.
error DelegateNotWhitelisted();

/// @dev Fee exceeded provided maximum fee percentage
error FeeExceedsMaxFee(uint256 fee, uint256 amount, uint256 maxFeePercentage);

/// @dev Common interface for the Position Manager.
interface IPositionManager is IFeeCollector {
    /// @dev New PositionManager contract is deployed.
    /// @param priceFeed Addres of the contract that provides price for collateral token.
    /// @param collateralToken Address of the token used as collateral.
    /// @param rToken Address of the rToken used by position manager.
    /// @param raftCollateralToken Address of Raft indexable collateral token.
    /// @param raftDebtToken Address of Raft indexable debt token.
    /// @param feeRecipient Fee recipient address.
    event PositionManagerDeployed(
        IPriceFeed priceFeed,
        IERC20 collateralToken,
        IRToken rToken,
        IERC20Indexable raftCollateralToken,
        IERC20Indexable raftDebtToken,
        address feeRecipient
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
    /// @param liquidator Liquidator that executed liquidation sequence.
    /// @param debtToOffset Total debt offset for the liquidation sequence.
    /// @param collToSendToProtocol Total collateral sent to protocol.
    /// @param collToSendToLiquidator Total collateral sent to liquidator.
    /// @param debtToRedistribute Total debt to redestribute to currently open positions.
    /// @param collToRedistribute Total collateral amount to redestribute to currently open positions.
    event Liquidation(
        address indexed liquidator,
        uint256 debtToOffset,
        uint256 collToSendToProtocol,
        uint256 collToSendToLiquidator,
        uint256 debtToRedistribute,
        uint256 collToRedistribute
    );

    /// @dev Position is liquidated.
    /// @param position Address of user that was the owner of the liquidated position.
    event PositionLiquidated(address indexed position);

    event LiquidationProtocolFeeChanged(uint256 _liquidationProtocolFee);
    event Redemption(
        uint256 _attemptedRAmount, uint256 _actualRAmount, uint256 _collateralTokenSent, uint256 _collateralTokenFee
    );

    event BorrowingSpreadUpdated(uint256 _borrowingSpread);
    event BaseRateUpdated(uint256 _baseRate);
    event LastFeeOpTimeUpdated(uint256 _lastFeeOpTime);

    struct LiquidationTotals {
        uint256 debtToOffset;
        uint256 collToSendToProtocol;
        uint256 collToSendToLiquidator;
        uint256 debtToRedistribute;
        uint256 collToRedistribute;
    }

    // --- Functions ---

    function setLiquidationProtocolFee(uint256 _liquidationProtocolFee) external;
    function liquidationProtocolFee() external view returns (uint256);
    function MAX_BORROWING_SPREAD() external view returns (uint256);
    function MAX_LIQUIDATION_PROTOCOL_FEE() external view returns (uint256);
    function collateralToken() external view returns (IERC20);
    function rToken() external view returns (IRToken);
    function priceFeed() external view returns (IPriceFeed);
    function globalDelegateWhitelist(address delegate) external view returns (bool isWhitelisted);
    function individualDelegateWhitelist(address borrower, address delegate)
        external
        view
        returns (bool isWhitelisted);

    function raftDebtToken() external view returns (IERC20Indexable);
    function raftCollateralToken() external view returns (IERC20Indexable);

    function sortedPositions() external view returns (address first, address last, uint256 maxSize, uint256 size);

    function sortedPositionsNodes(address _id) external view returns (bool exists, address nextId, address prevId);

    function getNominalICR(address _borrower) external view returns (uint256);
    function getCurrentICR(address _borrower, uint256 _price) external view returns (uint256);

    function liquidate(address _borrower) external;
    function batchLiquidatePositions(address[] calldata _positionArray) external;

    function redeemCollateral(
        uint256 _rAmount,
        address _firstRedemptionHint,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint256 _partialRedemptionHintNICR,
        uint256 _maxIterations,
        uint256 _maxFee
    ) external;

    function simulateBatchLiquidatePositions(address[] memory _positionArray, uint256 _price)
        external
        view
        returns (LiquidationTotals memory totals);

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
        address _borrower,
        uint256 _collChange,
        bool _isCollIncrease,
        uint256 _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external;

    function managePosition(
        uint256 _collChange,
        bool _isCollIncrease,
        uint256 _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external;

    function whitelistDelegate(address delegate) external;
}
