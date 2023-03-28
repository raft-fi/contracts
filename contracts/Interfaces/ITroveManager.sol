// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./ILiquityBase.sol";
import "./IRToken.sol";

/// @dev Max fee percentage must be between borrowing spread and 100%.
error TroveManagerInvalidMaxFeePercentage();

/// @dev Trove is active.
error TroveMaangerTroveActive();

/// @dev Dependencies' addresses have already been set.
error TroveManagerAddressesAlreadySet();

/// @dev Dependencies' addresses have not been set yet.
error TroveManagerAddressesNotSet();

/// @dev Max fee percentage must be between 0.5% and 100%.
error TroveManagerMaxFeePercentageOutOfRange();

/// @dev Redemptions are not allowed during bootstrap phase.
error TroveManagerRedemptionNotAllowed();

/// @dev Trove is not active (either does not exist or closed).
error TroveManagerTroveNotActive();

/// @dev Requested redemption amount is > user's R token balance.
error TroveManagerRedemptionAmountExceedsBalance();

/// @dev Only one trove in the system.
error TroveManagerOnlyOneTroveInSystem();

/// @dev Amount is zero.
error TroveManagerAmountIsZero();

/// @dev Cannot redeem when TCR < MCR.
error TroveManagerRedemptionTCRBelowMCR();

/// @dev Nothing to liquidate.
error NothingToLiquidate();

/// @dev Unable to redeem any amount.
error UnableToRedeemAnyAmount();

/// @dev Trove array must is empty.
error TroveArrayEmpty();

/// @dev Fee would eat up all returned collateral.
error FeeEatsUpAllReturnedCollateral();

/// @dev Borrowing spread exceeds maximum.
error BorrowingSpreadExceedsMaximum();

/// @dev Debt increase requires non-zero debt change.
error DebtIncreaseZeroDebtChange();

/// @dev Cannot withdraw and add collateral at the same time.
error NotSingularCollateralChange();

/// @dev There must be either a collateral change or a debt change.
error NoCollateralOrDebtChange();

/// @dev An operation that would result in ICR < MCR is not permitted.
error NewICRLowerThanMCR(uint256 newICR);

/// @dev Trove's net debt must be greater than minimum.
error NetDebtBelowMinimum(uint256 netDebt);

/// @dev Amount repaid must not be larger than the Trove's debt.
error RepayRAmountExceedsDebt(uint256 debt);

/// @dev Caller doesn't have enough R to make repayment.
error RepayNotEnoughR(uint256 amount);


// Common interface for the Trove Manager.
interface ITroveManager is ILiquityBase {
    enum TroveStatus {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation,
        closedByRedemption
    }

    enum TroveManagerOperation {
        applyPendingRewards,
        liquidate,
        redeemCollateral,
        openTrove,
        closeTrove,
        adjustTrove
    }

    // --- Events ---

    event PriceFeedAddressChanged(address _newPriceFeedAddress);
    event RTokenAddressChanged(address _newRTokenAddress);
    event ActivePoolAddressChanged(address _activePoolAddress);
    event DefaultPoolAddressChanged(address _defaultPoolAddress);
    event SortedTrovesAddressChanged(address _sortedTrovesAddress);
    event FeeRecipientChanged(address _feeRecipient);

    event Liquidation(uint _liquidatedDebt, uint _liquidatedColl, uint _collGasCompensation, uint _RGasCompensation);
    event Redemption(uint _attemptedRAmount, uint _actualRAmount, uint _collateralTokenSent, uint _collateralTokenFee);
    event TroveUpdated(address indexed _borrower, uint _debt, uint _coll, uint _stake, TroveManagerOperation _operation);
    event TroveLiquidated(address indexed _borrower, uint _debt, uint _coll, TroveManagerOperation _operation);
    event BorrowingSpreadUpdated(uint256 _borrowingSpread);
    event BaseRateUpdated(uint _baseRate);
    event LastFeeOpTimeUpdated(uint _lastFeeOpTime);
    event TotalStakesUpdated(uint _newTotalStakes);
    event SystemSnapshotsUpdated(uint _totalStakesSnapshot, uint _totalCollateralSnapshot);
    event LTermsUpdated(uint _L_CollateralBalance, uint _L_RDebt);
    event TroveSnapshotsUpdated(uint _L_CollateralBalance, uint _L_RDebt);
    event TroveIndexUpdated(address _borrower, uint _newIndex);
    event TroveCreated(address indexed _borrower, uint arrayIndex);
    event RBorrowingFeePaid(address indexed _borrower, uint _rFee);

    // --- Functions ---

    function setAddresses(
        address _activePoolAddress,
        address _defaultPoolAddress,
        address _priceFeedAddress,
        address _rTokenAddress,
        address _sortedTrovesAddress,
        address _feeRecipient
    ) external;

    function deploymentStartTime() external view returns (uint);

    function setFeeRecipient(address _feeRecipient) external;
    function feeRecipient() external view returns (address);

    function rToken() external view returns (IRToken);

    function getTroveOwnersCount() external view returns (uint);

    function getTroveFromTroveOwnersArray(uint _index) external view returns (address);

    function getNominalICR(address _borrower) external view returns (uint);
    function getCurrentICR(address _borrower, uint _price) external view returns (uint);

    function liquidate(address _borrower) external;

    function liquidateTroves(uint _n) external;

    function batchLiquidateTroves(address[] calldata _troveArray) external;

    function redeemCollateral(
        uint _rAmount,
        address _firstRedemptionHint,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint _partialRedemptionHintNICR,
        uint _maxIterations,
        uint _maxFee
    ) external;

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

    function getTroveStatus(address _borrower) external view returns (TroveStatus);

    function getTroveStake(address _borrower) external view returns (uint);

    function getTroveDebt(address _borrower) external view returns (uint);

    function getTroveColl(address _borrower) external view returns (uint);

    function getTCR(uint _price) external view returns (uint);

    function openTrove(uint _maxFee, uint _rAmount, address _upperHint, address _lowerHint, uint _amount) external;

    function addColl(address _upperHint, address _lowerHint, uint _amount) external;

    function withdrawColl(uint _amount, address _upperHint, address _lowerHint) external;

    function withdrawR(uint _maxFee, uint _amount, address _upperHint, address _lowerHint) external;

    function repayR(uint _amount, address _upperHint, address _lowerHint) external;

    function closeTrove() external;

    function adjustTrove(uint _maxFee, uint _collWithdrawal, uint _debtChange, bool isDebtIncrease, address _upperHint, address _lowerHint, uint _amount) external;

    function getCompositeDebt(uint _debt) external pure returns (uint);
}
