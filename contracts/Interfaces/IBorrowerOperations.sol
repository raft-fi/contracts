// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

/// @dev Dependencies' addresses have already been set.
error BorrowerOperationsAddressesAlreadySet();

/// @dev Dependencies' addresses have not been set yet.
error BorrowerOperationsAddressesNotSet();

/// @dev Trove is active.
error BorrowerOperationsTroveActive();

/// @dev Trove is not active (either does not exist or closed).
error BorrowerOperationsTroveNotActive();

/// @dev Max fee percentage must be between borrowing spread and 100%.
error BorrowerOperationsInvalidMaxFeePercentage();

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
interface IBorrowerOperations {
    enum BorrowerOperation {
        openTrove,
        closeTrove,
        adjustTrove
    }

    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event ActivePoolAddressChanged(address _activePoolAddress);
    event DefaultPoolAddressChanged(address _defaultPoolAddress);
    event CollSurplusPoolAddressChanged(address _collSurplusPoolAddress);
    event PriceFeedAddressChanged(address  _newPriceFeedAddress);
    event SortedTrovesAddressChanged(address _sortedTrovesAddress);
    event RTokenAddressChanged(address _rTokenAddress);
    event FeeRecipientChanged(address _feeRecipient);

    event TroveCreated(address indexed _borrower, uint arrayIndex);
    event TroveUpdated(address indexed _borrower, uint _debt, uint _coll, uint stake, BorrowerOperation operation);
    event RBorrowingFeePaid(address indexed _borrower, uint _rFee);

    // --- Functions ---

    function setAddresses(
        address _troveManagerAddress,
        address _activePoolAddress,
        address _defaultPoolAddress,
        address _collSurplusPoolAddress,
        address _priceFeedAddress,
        address _sortedTrovesAddress,
        address _rTokenAddress,
        address _feeRecipient
    ) external;

    function setFeeRecipient(address _feeRecipient) external;
    function feeRecipient() external view returns (address);

    function openTrove(uint _maxFee, uint _rAmount, address _upperHint, address _lowerHint, uint _amount) external;

    function addColl(address _upperHint, address _lowerHint, uint _amount) external;

    function withdrawColl(uint _amount, address _upperHint, address _lowerHint) external;

    function withdrawR(uint _maxFee, uint _amount, address _upperHint, address _lowerHint) external;

    function repayR(uint _amount, address _upperHint, address _lowerHint) external;

    function closeTrove() external;

    function adjustTrove(uint _maxFee, uint _collWithdrawal, uint _debtChange, bool isDebtIncrease, address _upperHint, address _lowerHint, uint _amount) external;

    function claimCollateral() external;

    function getCompositeDebt(uint _debt) external pure returns (uint);
}
