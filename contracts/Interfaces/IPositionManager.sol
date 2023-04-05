// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IFeeCollector.sol";
import "./IPriceFeed.sol";
import "./IRToken.sol";

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

/// @dev Amount repaid must not be larger than the Position's debt.
/// @param debt Debt amount that is larget than position's actual debt.
error RepayRAmountExceedsDebt(uint256 debt);

/// @dev The provided Liquidation Protocol Fee is out of the allowed bound.
error LiquidationProtocolFeeOutOfBound();

/// @dev Common interface for the Position Manager.
interface IPositionManager is IFeeCollector {
    /// @dev New PositionManager contract is deployed.
    /// @param priceFeed Addres of the contract that provides price for collateral token.
    /// @param collateralToken Address of the token used as collateral.
    /// @param rToken Address of the rToken used by position manager.
    /// @param feeRecipient Fee recipient address.
    event PositionManagerDeployed(
        IPriceFeed priceFeed,
        IERC20 collateralToken,
        IRToken rToken,
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
    event RBorrowingFeePaid(address indexed position, uint feeAmount);

    event LiquidationProtocolFeeChanged(uint256 _liquidationProtocolFee);

    event Liquidation(uint _liquidatedDebt, uint _liquidatedColl, uint _liquidationProtocolFee, uint _collGasCompensation, uint _RGasCompensation);
    event Redemption(uint _attemptedRAmount, uint _actualRAmount, uint _collateralTokenSent, uint _collateralTokenFee);
    event PositionLiquidated(address indexed _borrower, uint _debt, uint _coll);
    event BorrowingSpreadUpdated(uint256 _borrowingSpread);
    event BaseRateUpdated(uint _baseRate);
    event LastFeeOpTimeUpdated(uint _lastFeeOpTime);
    event StakesUpdated(address _borrower, uint256 _newStake, uint256 _newTotalStakes);
    event SystemSnapshotsUpdated(uint _totalStakesSnapshot, uint _totalCollateralSnapshot);
    event LTermsUpdated(uint _L_CollateralBalance, uint _L_RDebt);
    event PositionSnapshotsUpdated(uint _L_CollateralBalance, uint _L_RDebt);

    struct LiquidationTotals {
        uint totalCollInSequence;
        uint totalDebtInSequence;
        uint totalCollGasCompensation;
        uint totalRGasCompensation;
        uint totalDebtToOffset;
        uint totalCollToSendToProtocol;
        uint totalCollToSendToLiquidator;
        uint totalDebtToRedistribute;
        uint totalCollToRedistribute;
    }

    // --- Functions ---

    function setLiquidationProtocolFee(uint256 _liquidationProtocolFee) external;
    function liquidationProtocolFee() external view returns (uint256);
    function MAX_BORROWING_SPREAD() external view returns (uint256);
    function MAX_LIQUIDATION_PROTOCOL_FEE() external view returns (uint256);
    function collateralToken() external view returns (IERC20);
    function rToken() external view returns (IRToken);
    function priceFeed() external view returns (IPriceFeed);

    function positions(address _borrower) external view returns (uint debt, uint coll, uint stake);

    function sortedPositions() external view returns (address first, address last, uint256 maxSize, uint256 size);

    function sortedPositionsNodes(address _id) external view returns(bool exists, address nextId, address prevId);

    function totalStakes() external view returns (uint256);

    function rewardSnapshots(address _borrower) external view returns (uint256 collateralBalance, uint256 debtBalance);

    function getNominalICR(address _borrower) external view returns (uint);
    function getCurrentICR(address _borrower, uint _price) external view returns (uint);

    function liquidate(address _borrower) external;
    function batchLiquidatePositions(address[] calldata _positionArray) external;

    function L_CollateralBalance() external view returns (uint256);
    function L_RDebt() external view returns (uint256);

    function redeemCollateral(
        uint _rAmount,
        address _firstRedemptionHint,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint _partialRedemptionHintNICR,
        uint _maxIterations,
        uint _maxFee
    ) external;

    function simulateBatchLiquidatePositions(address[] memory _positionArray, uint256 _price) external view returns (LiquidationTotals memory totals);

    function getPendingCollateralTokenReward(address _borrower) external view returns (uint);

    function getPendingRDebtReward(address _borrower) external view returns (uint);

    function hasPendingRewards(address _borrower) external view returns (bool);

    function getEntireDebtAndColl(address _borrower) external view returns (
        uint debt,
        uint coll,
        uint pendingRDebtReward,
        uint pendingCollateralTokenReward
    );

    function getRedemptionRate() external view returns (uint);
    function getRedemptionRateWithDecay() external view returns (uint);

    function getRedemptionFeeWithDecay(uint _collateralTokenDrawn) external view returns (uint);

    function borrowingSpread() external view returns (uint256);
    function setBorrowingSpread(uint256 _borrowingSpread) external;

    function getBorrowingRate() external view returns (uint);
    function getBorrowingRateWithDecay() external view returns (uint);

    function getBorrowingFee(uint rDebt) external view returns (uint);
    function getBorrowingFeeWithDecay(uint _rDebt) external view returns (uint);

    function closePosition() external;
    
    function managePosition(
        uint256 _collChange,
        bool _isCollIncrease,
        uint256 _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external;
}
