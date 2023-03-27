// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

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
    event GasPoolAddressChanged(address _gasPoolAddress);
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
        address _gasPoolAddress,
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
