// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./Interfaces/ITroveManager.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/IRToken.sol";
import "./Interfaces/ISortedTroves.sol";
import "./Dependencies/LiquityBase.sol";
import "./Dependencies/BorrowerOperationsDependent.sol";
import "./Dependencies/CheckContract.sol";

contract TroveManager is LiquityBase, Ownable2Step, CheckContract, BorrowerOperationsDependent, ITroveManager {
    string constant public NAME = "TroveManager";

    // --- Connected contract declarations ---

    ICollSurplusPool collSurplusPool;

    IRToken public override rToken;

    address public override feeRecipient;

    // A doubly linked list of Troves, sorted by their sorted by their collateral ratios
    ISortedTroves public sortedTroves;

    // --- Data structures ---

    uint constant public SECONDS_IN_ONE_MINUTE = 60;
    /*
     * Half-life of 12h. 12h = 720 min
     * (1/2) = d^720 => d = (1/2)^(1/720)
     */
    uint256 public constant MINUTE_DECAY_FACTOR = 999037758833783000;
    uint256 public constant REDEMPTION_FEE_FLOOR = DECIMAL_PRECISION / 1000 * 5; // 0.5%
    uint256 public constant MAX_BORROWING_SPREAD = DECIMAL_PRECISION / 100; // 1%
    uint256 public constant MAX_BORROWING_FEE = DECIMAL_PRECISION / 100 * 5; // 5%

    // During bootsrap period redemptions are not allowed
    uint constant public BOOTSTRAP_PERIOD = 14 days;

    /*
    * BETA: 18 digit decimal. Parameter by which to divide the redeemed fraction, in order to calc the new base rate from a redemption.
    * Corresponds to (1 / ALPHA) in the white paper.
    */
    uint constant public BETA = 2;

    uint public immutable override deploymentStartTime;

    uint256 public override borrowingSpread;
    uint256 public baseRate;

    // The timestamp of the latest fee operation (redemption or new R issuance)
    uint public lastFeeOperationTime;

    // Store the necessary data for a trove
    struct Trove {
        uint debt;
        uint coll;
        uint stake;
        TroveStatus status;
        uint128 arrayIndex;
    }

    mapping (address => Trove) public Troves;

    uint public totalStakes;

    // Snapshot of the value of totalStakes, taken immediately after the latest liquidation
    uint public totalStakesSnapshot;

    // Snapshot of the total collateral across the ActivePool and DefaultPool, immediately after the latest liquidation.
    uint public totalCollateralSnapshot;

    /*
    * L_CollateralBalance and L_RDebt track the sums of accumulated liquidation rewards per unit staked. During its lifetime, each stake earns:
    *
    * An collateralToken gain of ( stake * [L_CollateralBalance - L_CollateralBalance(0)] )
    * A rDebt increase  of ( stake * [L_RDebt - L_RDebt(0)] )
    *
    * Where L_CollateralBalance(0) and L_RDebt(0) are snapshots of L_CollateralBalance and L_RDebt for the active Trove taken at the instant the stake was made
    */
    uint public L_CollateralBalance;
    uint public L_RDebt;

    // Map addresses with active troves to their RewardSnapshot
    mapping (address => RewardSnapshot) public rewardSnapshots;

    // Object containing the CollateralToken and R snapshots for a given active trove
    struct RewardSnapshot { uint collateralBalance; uint rDebt;}

    // Array of all active trove addresses - used to to compute an approximate hint off-chain, for the sorted list insertion
    address[] public TroveOwners;

    // Error trackers for the trove redistribution calculation
    uint public lastCollateralTokenError_Redistribution;
    uint public lastRDebtError_Redistribution;

    bool private _addressesSet;

    /*
    * --- Variable container structs for liquidations ---
    *
    * These structs are used to hold, return and assign variables inside the liquidation functions,
    * in order to avoid the error: "CompilerError: Stack too deep".
    **/

    struct LocalVariables_OuterLiquidationFunction {
        uint price;
        uint liquidatedDebt;
        uint liquidatedColl;
    }

    struct LocalVariables_InnerSingleLiquidateFunction {
        uint collToLiquidate;
        uint pendingDebtReward;
        uint pendingCollReward;
    }

    struct LocalVariables_LiquidationSequence {
        uint i;
        uint ICR;
        address user;
        uint entireSystemDebt;
        uint entireSystemColl;
    }

    struct LiquidationValues {
        uint entireTroveDebt;
        uint entireTroveColl;
        uint collGasCompensation;
        uint rGasCompensation;
        uint debtToOffset;
        uint collToSendToLiquidator;
        uint debtToRedistribute;
        uint collToRedistribute;
    }

    struct LiquidationTotals {
        uint totalCollInSequence;
        uint totalDebtInSequence;
        uint totalCollGasCompensation;
        uint totalRGasCompensation;
        uint totalDebtToOffset;
        uint totalCollToSendToLiquidator;
        uint totalDebtToRedistribute;
        uint totalCollToRedistribute;
    }

    struct ContractsCache {
        IActivePool activePool;
        IDefaultPool defaultPool;
        IRToken rToken;
        ISortedTroves sortedTroves;
        ICollSurplusPool collSurplusPool;
        address feeRecipient;
    }
    // --- Variable container structs for redemptions ---

    struct RedemptionTotals {
        uint remainingR;
        uint totalRToRedeem;
        uint totalCollateralTokenDrawn;
        uint collateralTokenFee;
        uint collateralTokenToSendToRedeemer;
        uint decayedBaseRate;
        uint price;
        uint totalRSupplyAtStart;
    }

    struct SingleRedemptionValues {
        uint rLot;
        uint collateralTokenLot;
        bool cancelledPartial;
    }

    // --- Constructor ---

    constructor() {
        deploymentStartTime = block.timestamp;
    }

    // --- Setters ---

    function setAddresses(
        IBorrowerOperations _borrowerOperations,
        address _activePoolAddress,
        address _defaultPoolAddress,
        address _collSurplusPoolAddress,
        address _priceFeedAddress,
        address _rTokenAddress,
        address _sortedTrovesAddress,
        address _feeRecipient
    ) external override onlyOwner {
        if (_addressesSet) {
            revert TroveManagerAddressesAlreadySet();
        }

        checkContract(_activePoolAddress);
        checkContract(_defaultPoolAddress);
        checkContract(_collSurplusPoolAddress);
        checkContract(_priceFeedAddress);
        checkContract(_rTokenAddress);
        checkContract(_sortedTrovesAddress);

        setBorrowerOperations(_borrowerOperations);
        activePool = IActivePool(_activePoolAddress);
        defaultPool = IDefaultPool(_defaultPoolAddress);
        collSurplusPool = ICollSurplusPool(_collSurplusPoolAddress);
        priceFeed = IPriceFeed(_priceFeedAddress);
        rToken = IRToken(_rTokenAddress);
        sortedTroves = ISortedTroves(_sortedTrovesAddress);
        feeRecipient = _feeRecipient;

        _addressesSet = true;

        emit ActivePoolAddressChanged(_activePoolAddress);
        emit DefaultPoolAddressChanged(_defaultPoolAddress);
        emit CollSurplusPoolAddressChanged(_collSurplusPoolAddress);
        emit PriceFeedAddressChanged(_priceFeedAddress);
        emit RTokenAddressChanged(_rTokenAddress);
        emit SortedTrovesAddressChanged(_sortedTrovesAddress);
        emit FeeRecipientChanged(_feeRecipient);
    }

    function setFeeRecipient(address _feeRecipient) external override onlyOwner {
        if (! _addressesSet) {
            revert TroveManagerAddressesNotSet();
        }
        feeRecipient = _feeRecipient;
        emit FeeRecipientChanged(_feeRecipient);
    }

    // --- Getters ---

    function getTroveOwnersCount() external view override returns (uint) {
        return TroveOwners.length;
    }

    function getTroveFromTroveOwnersArray(uint _index) external view override returns (address) {
        return TroveOwners[_index];
    }

    // --- Trove Liquidation functions ---

    // Single liquidation function. Closes the trove if its ICR is lower than the minimum collateral ratio.
    function liquidate(address _borrower) external override {
        _requireTroveIsActive(_borrower);

        address[] memory borrowers = new address[](1);
        borrowers[0] = _borrower;
        batchLiquidateTroves(borrowers);
    }

    // --- Inner single liquidation functions ---

    // Liquidate one trove
    function _liquidate(
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        address _borrower,
        uint _ICR
    )
        internal
        returns (LiquidationValues memory singleLiquidation)
    {
        LocalVariables_InnerSingleLiquidateFunction memory vars;

        (singleLiquidation.entireTroveDebt,
        singleLiquidation.entireTroveColl,
        vars.pendingDebtReward,
        vars.pendingCollReward) = getEntireDebtAndColl(_borrower);

        _movePendingTroveRewardsToActivePool(_activePool, _defaultPool, vars.pendingDebtReward, vars.pendingCollReward);
        _removeStake(_borrower);

        singleLiquidation.collGasCompensation = _getCollGasCompensation(singleLiquidation.entireTroveColl);
        singleLiquidation.rGasCompensation = R_GAS_COMPENSATION;
        uint collToLiquidate = singleLiquidation.entireTroveColl - singleLiquidation.collGasCompensation;

        if (_ICR <= _100pct) {
            singleLiquidation.debtToOffset = 0;
            singleLiquidation.collToSendToLiquidator = 0;
            singleLiquidation.debtToRedistribute = singleLiquidation.entireTroveDebt;
            singleLiquidation.collToRedistribute = collToLiquidate;
        }
        else {
            singleLiquidation.debtToOffset = singleLiquidation.entireTroveDebt;
            singleLiquidation.collToSendToLiquidator = collToLiquidate;
            singleLiquidation.debtToRedistribute = 0;
            singleLiquidation.collToRedistribute = 0;
        }

        _closeTrove(_borrower, TroveStatus.closedByLiquidation);
        emit TroveLiquidated(_borrower, singleLiquidation.entireTroveDebt, singleLiquidation.entireTroveColl, TroveManagerOperation.liquidate);
        emit TroveUpdated(_borrower, 0, 0, 0, TroveManagerOperation.liquidate);
        return singleLiquidation;
    }

    /*
    * Liquidate a sequence of troves. Closes a maximum number of n under-collateralized Troves,
    * starting from the one with the lowest collateral ratio in the system, and moving upwards
    */
    function liquidateTroves(uint _n) external override {
        ContractsCache memory contractsCache = ContractsCache(
            activePool,
            defaultPool,
            IRToken(address(0)),
            sortedTroves,
            ICollSurplusPool(address(0)),
            address(0)
        );
        LocalVariables_OuterLiquidationFunction memory vars;

        vars.price = priceFeed.fetchPrice();

        // Perform the appropriate liquidation sequence - tally the values, and obtain their totals
        LiquidationTotals memory totals = _getTotalsFromLiquidateTrovesSequence(contractsCache.activePool, contractsCache.defaultPool, vars.price, _n);

        if (totals.totalCollInSequence == 0) {
            revert NothingToLiquidate();
        }

        _offset(msg.sender, totals.totalDebtToOffset, totals.totalCollToSendToLiquidator);
        _redistributeDebtAndColl(contractsCache.activePool, contractsCache.defaultPool, totals.totalDebtToRedistribute, totals.totalCollToRedistribute);

        // Update system snapshots
        _updateSystemSnapshots_excludeCollRemainder(contractsCache.activePool, totals.totalCollGasCompensation);

        vars.liquidatedDebt = totals.totalDebtInSequence;
        vars.liquidatedColl = totals.totalCollInSequence - totals.totalCollGasCompensation;
        emit Liquidation(vars.liquidatedDebt, vars.liquidatedColl, totals.totalCollGasCompensation, totals.totalRGasCompensation);

        // Send gas compensation to caller
        _sendGasCompensation(contractsCache.activePool, msg.sender, totals.totalRGasCompensation, totals.totalCollGasCompensation);
    }

    function _getTotalsFromLiquidateTrovesSequence
    (
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        uint _price,
        uint _n
    )
        internal
        returns(LiquidationTotals memory totals)
    {
        LocalVariables_LiquidationSequence memory vars;
        LiquidationValues memory singleLiquidation;
        ISortedTroves sortedTrovesCached = sortedTroves;

        for (vars.i = 0; vars.i < _n; vars.i++) {
            vars.user = sortedTrovesCached.getLast();
            vars.ICR = getCurrentICR(vars.user, _price);

            if (vars.ICR < MCR) {
                singleLiquidation = _liquidate(_activePool, _defaultPool, vars.user, vars.ICR);

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);

            } else break;  // break if the loop reaches a Trove with ICR >= MCR
        }
    }

    /*
    * Attempt to liquidate a custom list of troves provided by the caller.
    */
    function batchLiquidateTroves(address[] memory _troveArray) public override {
        if (_troveArray.length == 0) {
            revert TroveArrayEmpty();
        }

        IActivePool activePoolCached = activePool;
        IDefaultPool defaultPoolCached = defaultPool;

        LocalVariables_OuterLiquidationFunction memory vars;

        vars.price = priceFeed.fetchPrice();

        // Perform the appropriate liquidation sequence - tally values and obtain their totals.
        LiquidationTotals memory totals = _getTotalsFromBatchLiquidate(activePoolCached, defaultPoolCached, vars.price, _troveArray);

        if (totals.totalCollInSequence == 0) {
            revert NothingToLiquidate();
        }

        _offset(msg.sender, totals.totalDebtToOffset, totals.totalCollToSendToLiquidator);
        _redistributeDebtAndColl(activePoolCached, defaultPoolCached, totals.totalDebtToRedistribute, totals.totalCollToRedistribute);

        // Update system snapshots
        _updateSystemSnapshots_excludeCollRemainder(activePoolCached, totals.totalCollGasCompensation);

        vars.liquidatedDebt = totals.totalDebtInSequence;
        vars.liquidatedColl = totals.totalCollInSequence - totals.totalCollGasCompensation;
        emit Liquidation(vars.liquidatedDebt, vars.liquidatedColl, totals.totalCollGasCompensation, totals.totalRGasCompensation);

        // Send gas compensation to caller
        _sendGasCompensation(activePoolCached, msg.sender, totals.totalRGasCompensation, totals.totalCollGasCompensation);
    }

    function _offset(address liquidator, uint256 debtToBurn, uint256 collToSendToLiquidator) internal {
        if (debtToBurn == 0) { return; }

        activePool.decreaseRDebt(debtToBurn);
        rToken.burn(liquidator, debtToBurn);
        activePool.withdrawCollateral(liquidator, collToSendToLiquidator);
    }

    function _getTotalsFromBatchLiquidate
    (
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        uint _price,
        address[] memory _troveArray
    )
        internal
        returns(LiquidationTotals memory totals)
    {
        LocalVariables_LiquidationSequence memory vars;
        LiquidationValues memory singleLiquidation;

        for (vars.i = 0; vars.i < _troveArray.length; vars.i++) {
            vars.user = _troveArray[vars.i];
            vars.ICR = getCurrentICR(vars.user, _price);

            if (vars.ICR < MCR) {
                singleLiquidation = _liquidate(_activePool, _defaultPool, vars.user, vars.ICR);

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);
            }
        }
    }

    // --- Liquidation helper functions ---

    function _addLiquidationValuesToTotals(LiquidationTotals memory oldTotals, LiquidationValues memory singleLiquidation)
    internal pure returns(LiquidationTotals memory newTotals) {

        // Tally all the values with their respective running totals
        newTotals.totalCollGasCompensation = oldTotals.totalCollGasCompensation + singleLiquidation.collGasCompensation;
        newTotals.totalRGasCompensation = oldTotals.totalRGasCompensation + singleLiquidation.rGasCompensation;
        newTotals.totalDebtInSequence = oldTotals.totalDebtInSequence + singleLiquidation.entireTroveDebt;
        newTotals.totalCollInSequence = oldTotals.totalCollInSequence + singleLiquidation.entireTroveColl;
        newTotals.totalDebtToOffset = oldTotals.totalDebtToOffset + singleLiquidation.debtToOffset;
        newTotals.totalCollToSendToLiquidator = oldTotals.totalCollToSendToLiquidator + singleLiquidation.collToSendToLiquidator;
        newTotals.totalDebtToRedistribute = oldTotals.totalDebtToRedistribute + singleLiquidation.debtToRedistribute;
        newTotals.totalCollToRedistribute = oldTotals.totalCollToRedistribute + singleLiquidation.collToRedistribute;

        return newTotals;
    }

    function _sendGasCompensation(IActivePool _activePool, address _liquidator, uint _R, uint _collateralToken) internal {
        if (_R > 0) {
            rToken.returnFromPool(address(borrowerOperations), _liquidator, _R);
        }

        if (_collateralToken > 0) {
            _activePool.withdrawCollateral(_liquidator, _collateralToken);
        }
    }

    // Move a Trove's pending debt and collateral rewards from distributions, from the Default Pool to the Active Pool
    function _movePendingTroveRewardsToActivePool(IActivePool _activePool, IDefaultPool _defaultPool, uint _R, uint _collateralToken) internal {
        _defaultPool.decreaseRDebt(_R);
        _activePool.increaseRDebt(_R);

        _defaultPool.withdrawCollateral(address(this), _collateralToken);
        IERC20(_defaultPool.collateralToken()).approve(address(_activePool), _collateralToken);
        _activePool.depositCollateral(address(this), _collateralToken);
    }

    // --- Redemption functions ---

    // Redeem as much collateral as possible from _borrower's Trove in exchange for R up to _maxRamount
    function _redeemCollateralFromTrove(
        ContractsCache memory _contractsCache,
        address _borrower,
        uint _maxRamount,
        uint _price,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint _partialRedemptionHintNICR
    )
        internal returns (SingleRedemptionValues memory singleRedemption)
    {
        // Determine the remaining amount (lot) to be redeemed, capped by the entire debt of the Trove minus the liquidation reserve
        singleRedemption.rLot = Math.min(_maxRamount, Troves[_borrower].debt - R_GAS_COMPENSATION);

        // Get the CollateralTokenLot of equivalent value in USD
        singleRedemption.collateralTokenLot = singleRedemption.rLot * DECIMAL_PRECISION / _price;

        // Decrease the debt and collateral of the current Trove according to the R lot and corresponding collateralToken to send
        uint newDebt = Troves[_borrower].debt - singleRedemption.rLot;
        uint newColl = Troves[_borrower].coll - singleRedemption.collateralTokenLot;

        if (newDebt == R_GAS_COMPENSATION) {
            // No debt left in the Trove (except for the liquidation reserve), therefore the trove gets closed
            _removeStake(_borrower);
            _closeTrove(_borrower, TroveStatus.closedByRedemption);
            _redeemCloseTrove(_contractsCache, _borrower, R_GAS_COMPENSATION, newColl);
            emit TroveUpdated(_borrower, 0, 0, 0, TroveManagerOperation.redeemCollateral);

        } else {
            uint newNICR = LiquityMath._computeNominalCR(newColl, newDebt);

            /*
            * If the provided hint is out of date, we bail since trying to reinsert without a good hint will almost
            * certainly result in running out of gas.
            *
            * If the resultant net debt of the partial is less than the minimum, net debt we bail.
            */
            if (newNICR != _partialRedemptionHintNICR || _getNetDebt(newDebt) < MIN_NET_DEBT) {
                singleRedemption.cancelledPartial = true;
                return singleRedemption;
            }

            _contractsCache.sortedTroves.reInsert(_borrower, newNICR, _upperPartialRedemptionHint, _lowerPartialRedemptionHint);

            Troves[_borrower].debt = newDebt;
            Troves[_borrower].coll = newColl;
            _updateStakeAndTotalStakes(_borrower);

            emit TroveUpdated(
                _borrower,
                newDebt, newColl,
                Troves[_borrower].stake,
                TroveManagerOperation.redeemCollateral
            );
        }

        return singleRedemption;
    }

    /*
    * Called when a full redemption occurs, and closes the trove.
    * The redeemer swaps (debt - liquidation reserve) R for (debt - liquidation reserve) worth of collateralToken, so the R liquidation reserve left corresponds to the remaining debt.
    * In order to close the trove, the R liquidation reserve is burned, and the corresponding debt is removed from the active pool.
    * The debt recorded on the trove's struct is zero'd elswhere, in _closeTrove.
    * Any surplus collateralToken left in the trove, is sent to the Coll surplus pool, and can be later claimed by the borrower.
    */
    function _redeemCloseTrove(ContractsCache memory _contractsCache, address _borrower, uint _R, uint _collateralToken) internal {
        _contractsCache.rToken.burn(address(borrowerOperations), _R);
        // Update Active Pool R, and send collateralToken to account
        _contractsCache.activePool.decreaseRDebt(_R);

        // send collateralToken from Active Pool to CollSurplus Pool
        _contractsCache.collSurplusPool.accountSurplus(_borrower, _collateralToken);

        _contractsCache.activePool.withdrawCollateral(address(this), _collateralToken);
        IERC20(_contractsCache.activePool.collateralToken()).approve(address(_contractsCache.collSurplusPool), _collateralToken);
        _contractsCache.collSurplusPool.depositCollateral(address(this), _collateralToken);
    }

    function _isValidFirstRedemptionHint(ISortedTroves _sortedTroves, address _firstRedemptionHint, uint _price) internal view returns (bool) {
        if (_firstRedemptionHint == address(0) ||
            !_sortedTroves.contains(_firstRedemptionHint) ||
            getCurrentICR(_firstRedemptionHint, _price) < MCR
        ) {
            return false;
        }

        address nextTrove = _sortedTroves.getNext(_firstRedemptionHint);
        return nextTrove == address(0) || getCurrentICR(nextTrove, _price) < MCR;
    }

    /* Send _rAmount R to the system and redeem the corresponding amount of collateral from as many Troves as are needed to fill the redemption
    * request.  Applies pending rewards to a Trove before reducing its debt and coll.
    *
    * Note that if _amount is very large, this function can run out of gas, specially if traversed troves are small. This can be easily avoided by
    * splitting the total _amount in appropriate chunks and calling the function multiple times.
    *
    * Param `_maxIterations` can also be provided, so the loop through Troves is capped (if it’s zero, it will be ignored).This makes it easier to
    * avoid OOG for the frontend, as only knowing approximately the average cost of an iteration is enough, without needing to know the “topology”
    * of the trove list. It also avoids the need to set the cap in stone in the contract, nor doing gas calculations, as both gas price and opcode
    * costs can vary.
    *
    * All Troves that are redeemed from -- with the likely exception of the last one -- will end up with no debt left, therefore they will be closed.
    * If the last Trove does have some remaining debt, it has a finite ICR, and the reinsertion could be anywhere in the list, therefore it requires a hint.
    * A frontend should use getRedemptionHints() to calculate what the ICR of this Trove will be after redemption, and pass a hint for its position
    * in the sortedTroves list along with the ICR value that the hint was found for.
    *
    * If another transaction modifies the list between calling getRedemptionHints() and passing the hints to redeemCollateral(), it
    * is very likely that the last (partially) redeemed Trove would end up with a different ICR than what the hint is for. In this case the
    * redemption will stop after the last completely redeemed Trove and the sender will keep the remaining R amount, which they can attempt
    * to redeem later.
    */
    function redeemCollateral(
        uint _rAmount,
        address _firstRedemptionHint,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint _partialRedemptionHintNICR,
        uint _maxIterations,
        uint _maxFeePercentage
    )
        external
        override
    {
        if (_maxFeePercentage < REDEMPTION_FEE_FLOOR || _maxFeePercentage > DECIMAL_PRECISION) {
            revert TroveManagerMaxFeePercentageOutOfRange();
        }
        if (block.timestamp < deploymentStartTime + BOOTSTRAP_PERIOD) {
            revert TroveManagerRedemptionNotAllowed();
        }

        ContractsCache memory contractsCache = ContractsCache(
            activePool,
            defaultPool,
            rToken,
            sortedTroves,
            collSurplusPool,
            feeRecipient
        );
        RedemptionTotals memory totals;

        totals.price = priceFeed.fetchPrice();
        _requireTCRoverMCR(totals.price);
        _requireAmountGreaterThanZero(_rAmount);
        _requireRBalanceCoversRedemption(contractsCache.rToken, msg.sender, _rAmount);

        totals.totalRSupplyAtStart = getEntireSystemDebt();
        // Confirm redeemer's balance is less than total R supply
        assert(contractsCache.rToken.balanceOf(msg.sender) <= totals.totalRSupplyAtStart);

        totals.remainingR = _rAmount;
        address currentBorrower;

        if (_isValidFirstRedemptionHint(contractsCache.sortedTroves, _firstRedemptionHint, totals.price)) {
            currentBorrower = _firstRedemptionHint;
        } else {
            currentBorrower = contractsCache.sortedTroves.getLast();
            // Find the first trove with ICR >= MCR
            while (currentBorrower != address(0) && getCurrentICR(currentBorrower, totals.price) < MCR) {
                currentBorrower = contractsCache.sortedTroves.getPrev(currentBorrower);
            }
        }

        // Loop through the Troves starting from the one with lowest collateral ratio until _amount of R is exchanged for collateral
        if (_maxIterations == 0) { _maxIterations = type(uint256).max; }
        while (currentBorrower != address(0) && totals.remainingR > 0 && _maxIterations > 0) {
            _maxIterations--;
            // Save the address of the Trove preceding the current one, before potentially modifying the list
            address nextUserToCheck = contractsCache.sortedTroves.getPrev(currentBorrower);

            _applyPendingRewards(contractsCache.activePool, contractsCache.defaultPool, currentBorrower);

            SingleRedemptionValues memory singleRedemption = _redeemCollateralFromTrove(
                contractsCache,
                currentBorrower,
                totals.remainingR,
                totals.price,
                _upperPartialRedemptionHint,
                _lowerPartialRedemptionHint,
                _partialRedemptionHintNICR
            );

            if (singleRedemption.cancelledPartial) break; // Partial redemption was cancelled (out-of-date hint, or new net debt < minimum), therefore we could not redeem from the last Trove

            totals.totalRToRedeem += singleRedemption.rLot;
            totals.totalCollateralTokenDrawn += singleRedemption.collateralTokenLot;

            totals.remainingR -= singleRedemption.rLot;
            currentBorrower = nextUserToCheck;
        }

        if (totals.totalCollateralTokenDrawn == 0) {
            revert UnableToRedeemAnyAmount();
        }

        // Decay the baseRate due to time passed, and then increase it according to the size of this redemption.
        // Use the saved total R supply value, from before it was reduced by the redemption.
        _updateBaseRateFromRedemption(totals.totalCollateralTokenDrawn, totals.price, totals.totalRSupplyAtStart);

        // Calculate the collateralToken fee
        totals.collateralTokenFee = _getRedemptionFee(totals.totalCollateralTokenDrawn);

        _requireUserAcceptsFee(totals.collateralTokenFee, totals.totalCollateralTokenDrawn, _maxFeePercentage);

        // Send the collateralToken fee to the recipient
        contractsCache.activePool.withdrawCollateral(feeRecipient, totals.collateralTokenFee);

        totals.collateralTokenToSendToRedeemer = totals.totalCollateralTokenDrawn - totals.collateralTokenFee;

        emit Redemption(_rAmount, totals.totalRToRedeem, totals.totalCollateralTokenDrawn, totals.collateralTokenFee);

        // Burn the total R that is cancelled with debt, and send the redeemed collateralToken to msg.sender
        contractsCache.rToken.burn(msg.sender, totals.totalRToRedeem);
        // Update Active Pool R, and send collateralToken to account
        contractsCache.activePool.decreaseRDebt(totals.totalRToRedeem);
        contractsCache.activePool.withdrawCollateral(msg.sender, totals.collateralTokenToSendToRedeemer);
    }

    // --- Helper functions ---

    // Return the nominal collateral ratio (ICR) of a given Trove, without the price. Takes a trove's pending coll and debt rewards from redistributions into account.
    function getNominalICR(address _borrower) public view override returns (uint nicr) {
        (uint currentCollateralToken, uint currentRDebt) = _getCurrentTroveAmounts(_borrower);

        nicr = LiquityMath._computeNominalCR(currentCollateralToken, currentRDebt);
    }

    // Return the current collateral ratio (ICR) of a given Trove. Takes a trove's pending coll and debt rewards from redistributions into account.
    function getCurrentICR(address _borrower, uint _price) public view override returns (uint icr) {
        (uint currentCollateralToken, uint currentRDebt) = _getCurrentTroveAmounts(_borrower);

        icr = LiquityMath._computeCR(currentCollateralToken, currentRDebt, _price);
    }

    function _getCurrentTroveAmounts(address _borrower) internal view returns (uint currentCollateralToken, uint currentRDebt) {
        currentCollateralToken = Troves[_borrower].coll + getPendingCollateralTokenReward(_borrower);
        currentRDebt = Troves[_borrower].debt + getPendingRDebtReward(_borrower);
    }

    function applyPendingRewards(address _borrower) external override onlyBorrowerOperations {
        return _applyPendingRewards(activePool, defaultPool, _borrower);
    }

    // Add the borrowers's coll and debt rewards earned from redistributions, to their Trove
    function _applyPendingRewards(IActivePool _activePool, IDefaultPool _defaultPool, address _borrower) internal {
        if (hasPendingRewards(_borrower)) {
            _requireTroveIsActive(_borrower);

            // Compute pending rewards
            uint pendingCollateralTokenReward = getPendingCollateralTokenReward(_borrower);
            uint pendingRDebtReward = getPendingRDebtReward(_borrower);

            // Apply pending rewards to trove's state
            Troves[_borrower].coll += pendingCollateralTokenReward;
            Troves[_borrower].debt += pendingRDebtReward;

            _updateTroveRewardSnapshots(_borrower);

            // Transfer from DefaultPool to ActivePool
            _movePendingTroveRewardsToActivePool(_activePool, _defaultPool, pendingRDebtReward, pendingCollateralTokenReward);

            emit TroveUpdated(
                _borrower,
                Troves[_borrower].debt,
                Troves[_borrower].coll,
                Troves[_borrower].stake,
                TroveManagerOperation.applyPendingRewards
            );
        }
    }

    // Update borrower's snapshots of L_CollateralBalance and L_RDebt to reflect the current values
    function updateTroveRewardSnapshots(address _borrower) external override onlyBorrowerOperations {
       return _updateTroveRewardSnapshots(_borrower);
    }

    function _updateTroveRewardSnapshots(address _borrower) internal {
        rewardSnapshots[_borrower].collateralBalance = L_CollateralBalance;
        rewardSnapshots[_borrower].rDebt = L_RDebt;
        emit TroveSnapshotsUpdated(L_CollateralBalance, L_RDebt);
    }

    // Get the borrower's pending accumulated collateralToken reward, earned by their stake
    function getPendingCollateralTokenReward(address _borrower) public view override returns (uint pendingCollateralTokenReward) {
        uint snapshotCollateralBalance = rewardSnapshots[_borrower].collateralBalance;
        uint rewardPerUnitStaked = L_CollateralBalance - snapshotCollateralBalance;

        if (rewardPerUnitStaked == 0 || Troves[_borrower].status != TroveStatus.active) { return 0; }

        pendingCollateralTokenReward = Troves[_borrower].stake * rewardPerUnitStaked / DECIMAL_PRECISION;
    }

    // Get the borrower's pending accumulated R reward, earned by their stake
    function getPendingRDebtReward(address _borrower) public view override returns (uint pendingRDebtReward) {
        uint snapshotRDebt = rewardSnapshots[_borrower].rDebt;
        uint rewardPerUnitStaked = L_RDebt - snapshotRDebt;

        if (rewardPerUnitStaked == 0 || Troves[_borrower].status != TroveStatus.active) { return 0; }

        pendingRDebtReward = Troves[_borrower].stake * rewardPerUnitStaked / DECIMAL_PRECISION;
    }

    function hasPendingRewards(address _borrower) public view override returns (bool) {
        /*
        * A Trove has pending rewards if its snapshot is less than the current rewards per-unit-staked sum:
        * this indicates that rewards have occured since the snapshot was made, and the user therefore has
        * pending rewards
        */
        return Troves[_borrower].status == TroveStatus.active && rewardSnapshots[_borrower].collateralBalance < L_CollateralBalance;
    }

    // Return the Troves entire debt and coll, including pending rewards from redistributions.
    function getEntireDebtAndColl(
        address _borrower
    )
        public
        view
        override
        returns (uint debt, uint coll, uint pendingRDebtReward, uint pendingCollateralTokenReward)
    {
        pendingRDebtReward = getPendingRDebtReward(_borrower);
        pendingCollateralTokenReward = getPendingCollateralTokenReward(_borrower);

        debt = Troves[_borrower].debt + pendingRDebtReward;
        coll = Troves[_borrower].coll + pendingCollateralTokenReward;
    }

    function removeStake(address _borrower) external override onlyBorrowerOperations {
        return _removeStake(_borrower);
    }

    // Remove borrower's stake from the totalStakes sum, and set their stake to 0
    function _removeStake(address _borrower) internal {
        uint stake = Troves[_borrower].stake;
        totalStakes = totalStakes - stake;
        Troves[_borrower].stake = 0;
    }

    function updateStakeAndTotalStakes(address _borrower) external override onlyBorrowerOperations returns (uint) {
        return _updateStakeAndTotalStakes(_borrower);
    }

    // Update borrower's stake based on their latest collateral value
    function _updateStakeAndTotalStakes(address _borrower) internal returns (uint newStake) {
        newStake = _computeNewStake(Troves[_borrower].coll);
        uint oldStake = Troves[_borrower].stake;
        Troves[_borrower].stake = newStake;

        totalStakes = totalStakes - oldStake + newStake;
        emit TotalStakesUpdated(totalStakes);
    }

    // Calculate a new stake based on the snapshots of the totalStakes and totalCollateral taken at the last liquidation
    function _computeNewStake(uint _coll) internal view returns (uint stake) {
        if (totalCollateralSnapshot == 0) {
            stake = _coll;
        } else {
            /*
            * The following assert() holds true because:
            * - The system always contains >= 1 trove
            * - When we close or liquidate a trove, we redistribute the pending rewards, so if all troves were closed/liquidated,
            * rewards would’ve been emptied and totalCollateralSnapshot would be zero too.
            */
            assert(totalStakesSnapshot > 0);
            stake = _coll * totalStakesSnapshot / totalCollateralSnapshot;
        }
    }

    function _redistributeDebtAndColl(IActivePool _activePool, IDefaultPool _defaultPool, uint _debt, uint _coll) internal {
        if (_debt == 0) { return; }

        /*
        * Add distributed coll and debt rewards-per-unit-staked to the running totals. Division uses a "feedback"
        * error correction, to keep the cumulative error low in the running totals L_CollateralBalance and L_RDebt:
        *
        * 1) Form numerators which compensate for the floor division errors that occurred the last time this
        * function was called.
        * 2) Calculate "per-unit-staked" ratios.
        * 3) Multiply each ratio back by its denominator, to reveal the current floor division error.
        * 4) Store these errors for use in the next correction when this function is called.
        * 5) Note: static analysis tools complain about this "division before multiplication", however, it is intended.
        */
        uint collateralTokenNumerator = _coll * DECIMAL_PRECISION + lastCollateralTokenError_Redistribution;
        uint RDebtNumerator = _debt * DECIMAL_PRECISION + lastRDebtError_Redistribution;

        // Get the per-unit-staked terms
        uint collateralTokenRewardPerUnitStaked = collateralTokenNumerator / totalStakes;
        uint RDebtRewardPerUnitStaked = RDebtNumerator / totalStakes;

        lastCollateralTokenError_Redistribution = collateralTokenNumerator - collateralTokenRewardPerUnitStaked * totalStakes;
        lastRDebtError_Redistribution = RDebtNumerator - RDebtRewardPerUnitStaked * totalStakes;

        // Add per-unit-staked terms to the running totals
        L_CollateralBalance += collateralTokenRewardPerUnitStaked;
        L_RDebt += RDebtRewardPerUnitStaked;

        emit LTermsUpdated(L_CollateralBalance, L_RDebt);

        // Transfer coll and debt from ActivePool to DefaultPool
        _activePool.decreaseRDebt(_debt);
        _defaultPool.increaseRDebt(_debt);
        _activePool.withdrawCollateral(address(this), _coll);
        IERC20(_activePool.collateralToken()).approve(address(_defaultPool), _coll);
        _defaultPool.depositCollateral(address(this), _coll);
    }

    function closeTrove(address _borrower) external override onlyBorrowerOperations {
        return _closeTrove(_borrower, TroveStatus.closedByOwner);
    }

    function _closeTrove(address _borrower, TroveStatus closedStatus) internal {
        assert(closedStatus != TroveStatus.nonExistent && closedStatus != TroveStatus.active);

        uint TroveOwnersArrayLength = TroveOwners.length;
        _requireMoreThanOneTroveInSystem(TroveOwnersArrayLength);

        Troves[_borrower].status = closedStatus;
        Troves[_borrower].coll = 0;
        Troves[_borrower].debt = 0;

        rewardSnapshots[_borrower].collateralBalance = 0;
        rewardSnapshots[_borrower].rDebt = 0;

        _removeTroveOwner(_borrower, TroveOwnersArrayLength);
        sortedTroves.remove(_borrower);
    }

    /*
    * Updates snapshots of system total stakes and total collateral, excluding a given collateral remainder from the calculation.
    * Used in a liquidation sequence.
    *
    * The calculation excludes a portion of collateral that is in the ActivePool:
    *
    * the total collateralToken gas compensation from the liquidation sequence
    *
    * The collateralToken as compensation must be excluded as it is always sent out at the very end of the liquidation sequence.
    */
    function _updateSystemSnapshots_excludeCollRemainder(IActivePool _activePool, uint _collRemainder) internal {
        totalStakesSnapshot = totalStakes;

        uint activeColl = _activePool.collateralBalance();
        uint liquidatedColl = defaultPool.collateralBalance();
        totalCollateralSnapshot = activeColl - _collRemainder + liquidatedColl;

        emit SystemSnapshotsUpdated(totalStakesSnapshot, totalCollateralSnapshot);
    }

    // Push the owner's address to the Trove owners list, and record the corresponding array index on the Trove struct
    function addTroveOwnerToArray(address _borrower) external override onlyBorrowerOperations returns (uint index) {
        index = _addTroveOwnerToArray(_borrower);
    }

    function _addTroveOwnerToArray(address _borrower) internal returns (uint128 index) {
        /* Max array size is 2**128 - 1, i.e. ~3e30 troves. No risk of overflow, since troves have minimum R
        debt of liquidation reserve plus MIN_NET_DEBT. 3e30 R dwarfs the value of all wealth in the world ( which is < 1e15 USD). */

        // Push the Troveowner to the array
        TroveOwners.push(_borrower);

        // Record the index of the new Troveowner on their Trove struct
        index = uint128(TroveOwners.length - 1);
        Troves[_borrower].arrayIndex = index;
    }

    /*
    * Remove a Trove owner from the TroveOwners array, not preserving array order. Removing owner 'B' does the following:
    * [A B C D E] => [A E C D], and updates E's Trove struct to point to its new array index.
    */
    function _removeTroveOwner(address _borrower, uint TroveOwnersArrayLength) internal {
        TroveStatus troveStatus = Troves[_borrower].status;
        // It’s set in caller function `_closeTrove`
        assert(troveStatus != TroveStatus.nonExistent && troveStatus != TroveStatus.active);

        uint128 index = Troves[_borrower].arrayIndex;
        uint length = TroveOwnersArrayLength;
        uint idxLast = length - 1;

        assert(index <= idxLast);

        address addressToMove = TroveOwners[idxLast];

        TroveOwners[index] = addressToMove;
        Troves[addressToMove].arrayIndex = index;
        emit TroveIndexUpdated(addressToMove, index);

        TroveOwners.pop();
    }

    // --- TCR functions ---

    function getTCR(uint _price) external view override returns (uint) {
        return _getTCR(_price);
    }

    // --- Redemption fee functions ---

    /*
    * This function has two impacts on the baseRate state variable:
    * 1) decays the baseRate based on time passed since last redemption or R borrowing operation.
    * then,
    * 2) increases the baseRate based on the amount redeemed, as a proportion of total supply
    */
    function _updateBaseRateFromRedemption(uint _collateralTokenDrawn,  uint _price, uint _totalRSupply) internal returns (uint) {
        uint decayedBaseRate = _calcDecayedBaseRate();

        /* Convert the drawn collateralToken back to R at face value rate (1 R:1 USD), in order to get
        * the fraction of total supply that was redeemed at face value. */
        uint redeemedRFraction = _collateralTokenDrawn * _price / _totalRSupply;

        uint newBaseRate = decayedBaseRate + redeemedRFraction / BETA;
        newBaseRate = Math.min(newBaseRate, DECIMAL_PRECISION); // cap baseRate at a maximum of 100%
        //assert(newBaseRate <= DECIMAL_PRECISION); // This is already enforced in the line above
        assert(newBaseRate > 0); // Base rate is always non-zero after redemption

        // Update the baseRate state variable
        baseRate = newBaseRate;
        emit BaseRateUpdated(newBaseRate);

        _updateLastFeeOpTime();

        return newBaseRate;
    }

    function getRedemptionRate() public view override returns (uint) {
        return _calcRedemptionRate(baseRate);
    }

    function getRedemptionRateWithDecay() public view override returns (uint) {
        return _calcRedemptionRate(_calcDecayedBaseRate());
    }

    function _calcRedemptionRate(uint _baseRate) internal pure returns (uint) {
        return Math.min(
            REDEMPTION_FEE_FLOOR + _baseRate,
            DECIMAL_PRECISION // cap at a maximum of 100%
        );
    }

    function _getRedemptionFee(uint _collateralTokenDrawn) internal view returns (uint) {
        return _calcRedemptionFee(getRedemptionRate(), _collateralTokenDrawn);
    }

    function getRedemptionFeeWithDecay(uint _collateralTokenDrawn) external view override returns (uint) {
        return _calcRedemptionFee(getRedemptionRateWithDecay(), _collateralTokenDrawn);
    }

    function _calcRedemptionFee(uint _redemptionRate, uint _collateralTokenDrawn) internal pure returns (uint redemptionFee) {
        redemptionFee = _redemptionRate * _collateralTokenDrawn / DECIMAL_PRECISION;
        if (redemptionFee >= _collateralTokenDrawn) {
            revert FeeEatsUpAllReturnedCollateral();
        }
    }

    // --- Borrowing fee functions ---

    function setBorrowingSpread(uint256 _borrowingSpread) external override onlyOwner {
        if (_borrowingSpread > MAX_BORROWING_SPREAD) {
            revert BorrowingSpreadExceedsMaximum();
        }
        borrowingSpread = _borrowingSpread;
        emit BorrowingSpreadUpdated(_borrowingSpread);
    }

    function getBorrowingRate() public view override returns (uint) {
        return _calcBorrowingRate(baseRate);
    }

    function getBorrowingRateWithDecay() public view override returns (uint) {
        return _calcBorrowingRate(_calcDecayedBaseRate());
    }

    function _calcBorrowingRate(uint256 _baseRate) internal view returns (uint256) {
        return Math.min(borrowingSpread + _baseRate, MAX_BORROWING_FEE);
    }

    function getBorrowingFee(uint _rDebt) external view override returns (uint) {
        return _calcBorrowingFee(getBorrowingRate(), _rDebt);
    }

    function getBorrowingFeeWithDecay(uint _rDebt) external view override returns (uint) {
        return _calcBorrowingFee(getBorrowingRateWithDecay(), _rDebt);
    }

    function _calcBorrowingFee(uint _borrowingRate, uint _rDebt) internal pure returns (uint) {
        return _borrowingRate * _rDebt / DECIMAL_PRECISION;
    }

    // Updates the baseRate state variable based on time elapsed since the last redemption or R borrowing operation.
    function decayBaseRateFromBorrowing() external override onlyBorrowerOperations {
        uint decayedBaseRate = _calcDecayedBaseRate();
        assert(decayedBaseRate <= DECIMAL_PRECISION);  // The baseRate can decay to 0

        baseRate = decayedBaseRate;
        emit BaseRateUpdated(decayedBaseRate);

        _updateLastFeeOpTime();
    }

    // --- Internal fee functions ---

    // Update the last fee operation time only if time passed >= decay interval. This prevents base rate griefing.
    function _updateLastFeeOpTime() internal {
        uint timePassed = block.timestamp - lastFeeOperationTime;

        if (timePassed >= SECONDS_IN_ONE_MINUTE) {
            lastFeeOperationTime = block.timestamp;
            emit LastFeeOpTimeUpdated(block.timestamp);
        }
    }

    function _calcDecayedBaseRate() internal view returns (uint) {
        uint minutesPassed = _minutesPassedSinceLastFeeOp();
        uint decayFactor = LiquityMath._decPow(MINUTE_DECAY_FACTOR, minutesPassed);

        return baseRate * decayFactor / DECIMAL_PRECISION;
    }

    function _minutesPassedSinceLastFeeOp() internal view returns (uint) {
        return (block.timestamp - lastFeeOperationTime) / SECONDS_IN_ONE_MINUTE;
    }

    // --- 'require' wrapper functions ---

    function _requireTroveIsActive(address _borrower) internal view {
        if (Troves[_borrower].status != TroveStatus.active) {
            revert TroveManagerTroveNotActive();
        }
    }

    function _requireRBalanceCoversRedemption(IRToken _rToken, address _redeemer, uint _amount) internal view {
        if (_rToken.balanceOf(_redeemer) < _amount) {
            revert TroveManagerRedemptionAmountExceedsBalance();
        }
    }

    function _requireMoreThanOneTroveInSystem(uint troveOwnersArrayLength) internal view {
        if (troveOwnersArrayLength <= 1 || sortedTroves.getSize() <= 1) {
            revert TroveManagerOnlyOneTroveInSystem();
        }
    }

    function _requireAmountGreaterThanZero(uint _amount) internal pure {
        if (_amount == 0) {
            revert TroveManagerAmountIsZero();
        }
    }

    function _requireTCRoverMCR(uint _price) internal view {
        if (_getTCR(_price) < MCR) {
            revert TroveManagerRedemptionTCRBelowMCR();
        }
    }

    // --- Trove property getters ---

    function getTroveStatus(address _borrower) external view override returns (TroveStatus) {
        return Troves[_borrower].status;
    }

    function getTroveStake(address _borrower) external view override returns (uint) {
        return Troves[_borrower].stake;
    }

    function getTroveDebt(address _borrower) external view override returns (uint) {
        return Troves[_borrower].debt;
    }

    function getTroveColl(address _borrower) external view override returns (uint) {
        return Troves[_borrower].coll;
    }

    // --- Trove property setters, called by BorrowerOperations ---

    function setTroveStatus(address _borrower, uint _num) external override onlyBorrowerOperations {
        Troves[_borrower].status = TroveStatus(_num);
    }

    function increaseTroveColl(address _borrower, uint _collIncrease) external override onlyBorrowerOperations returns (uint newColl) {
        newColl = Troves[_borrower].coll + _collIncrease;
        Troves[_borrower].coll = newColl;
    }

    function decreaseTroveColl(address _borrower, uint _collDecrease) external override onlyBorrowerOperations returns (uint newColl) {
        newColl = Troves[_borrower].coll - _collDecrease;
        Troves[_borrower].coll = newColl;
    }

    function increaseTroveDebt(address _borrower, uint _debtIncrease) external override onlyBorrowerOperations returns (uint newDebt) {
        newDebt = Troves[_borrower].debt + _debtIncrease;
        Troves[_borrower].debt = newDebt;
    }

    function decreaseTroveDebt(address _borrower, uint _debtDecrease) external override onlyBorrowerOperations returns (uint newDebt) {
        newDebt = Troves[_borrower].debt - _debtDecrease;
        Troves[_borrower].debt = newDebt;
    }
}
