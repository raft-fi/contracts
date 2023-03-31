// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./Interfaces/IPositionManager.sol";
import "./Interfaces/IRToken.sol";
import "./Dependencies/LiquityBase.sol";
import "./FeeCollector.sol";
import "./SortedPositions.sol";
import "./RToken.sol";

contract PositionManager is LiquityBase, FeeCollector, IPositionManager {
    using SortedPositions for SortedPositions.Data;
    string constant public NAME = "PositionManager";

    // --- Connected contract declarations ---

    IERC20 public immutable override collateralToken;
    IRToken public immutable override rToken;

    // A doubly linked list of Positions, sorted by their sorted by their collateral ratios
    SortedPositions.Data public override sortedPositions;

    // --- Pools ---

    uint256 private _activePoolCollateralBalance;
    uint256 private _defaultPoolCollateralBalance;

    /*
     * Half-life of 12h. 12h = 720 min
     * (1/2) = d^720 => d = (1/2)^(1/720)
     */
    uint256 public constant MINUTE_DECAY_FACTOR = 999037758833783000;
    uint256 public constant REDEMPTION_FEE_FLOOR = DECIMAL_PRECISION / 1000 * 5; // 0.5%
    uint256 public constant override MAX_BORROWING_SPREAD = DECIMAL_PRECISION / 100; // 1%
    uint256 public constant MAX_BORROWING_FEE = DECIMAL_PRECISION / 100 * 5; // 5%

    /*
    * BETA: 18 digit decimal. Parameter by which to divide the redeemed fraction, in order to calc the new base rate from a redemption.
    * Corresponds to (1 / ALPHA) in the white paper.
    */
    uint constant public BETA = 2;

    uint256 public override borrowingSpread;
    uint256 public baseRate;

    // The timestamp of the latest fee operation (redemption or new R issuance)
    uint public lastFeeOperationTime;

    // Store the necessary data for a position
    struct Position {
        uint debt;
        uint coll;
        uint stake;
        PositionStatus status;
    }

    mapping (address => Position) public override positions;

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
    * Where L_CollateralBalance(0) and L_RDebt(0) are snapshots of L_CollateralBalance and L_RDebt for the active Position taken at the instant the stake was made
    */
    uint public L_CollateralBalance;
    uint public L_RDebt;

    // Map addresses with active positions to their RewardSnapshot
    mapping (address => RewardSnapshot) public rewardSnapshots;

    // Object containing the CollateralToken and R snapshots for a given active position
    struct RewardSnapshot { uint collateralBalance; uint rDebt;}

    // Error trackers for the position redistribution calculation
    uint public lastCollateralTokenError_Redistribution;
    uint public lastRDebtError_Redistribution;

    /*
    * --- Variable container structs for liquidations ---
    *
    * These structs are used to hold, return and assign variables inside the liquidation functions,
    * in order to avoid the error: "CompilerError: Stack too deep".
    **/

     struct LocalVariables_adjustPosition {
        uint price;
        uint collChange;
        uint netDebtChange;
        bool isCollIncrease;
        uint debt;
        uint coll;
        uint oldICR;
        uint newICR;
        uint newNICR;
        uint rFee;
        uint newDebt;
        uint newColl;
        uint stake;
    }

    struct LiquidationValues {
        uint entirePositionDebt;
        uint entirePositionColl;
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
    // --- Variable container structs for redemptions ---

    struct SingleRedemptionValues {
        uint rLot;
        uint collateralTokenLot;
        bool cancelledPartial;
    }

    // --- Modifiers ---

    modifier validMaxFeePercentageWhen(uint256 _maxFeePercentage, bool condition) {
        if (condition && (_maxFeePercentage < borrowingSpread || _maxFeePercentage > DECIMAL_PRECISION)) {
            revert PositionManagerInvalidMaxFeePercentage();
        }
        _;
    }

    modifier onlyActivePosition() {
        if (positions[msg.sender].status != PositionStatus.active) {
            revert PositionManagerPositionNotActive();
        }
        _;
    }

    modifier onlyNonActivePosition() {
        if (positions[msg.sender].status == PositionStatus.active) {
            revert PositionMaangerPositionActive();
        }
        _;
    }

    // --- Constructor ---

    constructor(IPriceFeed _priceFeed, IERC20 _collateralToken, uint256 _positionsSize) FeeCollector(msg.sender) {
        priceFeed = _priceFeed;
        collateralToken = _collateralToken;
        rToken = new RToken(this, msg.sender);
        sortedPositions.maxSize = _positionsSize;

        emit PositionManagerDeployed(_priceFeed, _collateralToken, rToken, msg.sender);
    }

    // --- Borrower Position Operations ---

    function openPosition(
        uint _maxFeePercentage,
        uint _rAmount,
        address _upperHint,
        address _lowerHint,
        uint _collAmount
    )
        external
        override
        validMaxFeePercentageWhen(_maxFeePercentage, true)
        onlyNonActivePosition
    {
        uint256 rFee = _triggerBorrowingFee(rToken, _rAmount, _maxFeePercentage);
        uint256 netDebt = _rAmount + rFee;
        _requireAtLeastMinNetDebt(netDebt);

        // ICR is based on the composite debt, i.e. the requested R amount + R borrowing fee + R gas comp.
        uint256 compositeDebt = _getCompositeDebt(netDebt);
        assert(compositeDebt > 0);

        _requireICRisAboveMCR(LiquityMath._computeCR(_collAmount, compositeDebt, priceFeed.fetchPrice()));

        // Set the position struct's properties
        positions[msg.sender].status = PositionStatus.active;
        positions[msg.sender].coll = _collAmount;
        positions[msg.sender].debt = compositeDebt;

        _updatePositionRewardSnapshots(msg.sender);
        uint256 stake = _updateStakeAndTotalStakes(msg.sender);

        sortedPositions.insert(
            this, msg.sender, LiquityMath._computeNominalCR(_collAmount, compositeDebt), _upperHint, _lowerHint
        );
        emit PositionCreated(msg.sender);

        // Move the collateralToken to the Active Pool, and mint the rAmount to the borrower
        _activePoolCollateralBalance += _collAmount;
        collateralToken.transferFrom(msg.sender, address(this), _collAmount);
        rToken.mint(msg.sender, _rAmount);

        // Move the R gas compensation to the Gas Pool
        rToken.mint(address(this), R_GAS_COMPENSATION);

        emit PositionUpdated(msg.sender, compositeDebt, _collAmount, stake, PositionManagerOperation.openPosition);
        emit RBorrowingFeePaid(msg.sender, rFee);
    }

    // Send collateralToken to a position
    function addColl(address _upperHint, address _lowerHint, uint256 _collDeposit) external override {
        _adjustPosition(0, 0, false, _upperHint, _lowerHint, 0, _collDeposit);
    }

    // Withdraw collateralToken from a position
    function withdrawColl(uint _collWithdrawal, address _upperHint, address _lowerHint) external override {
        _adjustPosition(_collWithdrawal, 0, false, _upperHint, _lowerHint, 0, 0);
    }

    // Withdraw R tokens from a position: mint new R tokens to the owner, and increase the position's debt accordingly
    function withdrawR(uint _maxFeePercentage, uint _rAmount, address _upperHint, address _lowerHint) external override {
        _adjustPosition(0, _rAmount, true, _upperHint, _lowerHint, _maxFeePercentage, 0);
    }

    // Repay R tokens to a Position: Burn the repaid R tokens, and reduce the position's debt accordingly
    function repayR(uint _rAmount, address _upperHint, address _lowerHint) external override {
        _adjustPosition(0, _rAmount, false, _upperHint, _lowerHint, 0, 0);
    }

    function adjustPosition(uint _maxFeePercentage, uint _collWithdrawal, uint _rChange, bool _isDebtIncrease, address _upperHint, address _lowerHint, uint256 _collDeposit) external override {
        _adjustPosition(_collWithdrawal, _rChange, _isDebtIncrease, _upperHint, _lowerHint, _maxFeePercentage, _collDeposit);
    }

    /*
    * _adjustPosition(): Alongside a debt change, this function can perform either a collateral top-up or a collateral withdrawal.
    *
    * It therefore expects either a positive _collDeposit, or a positive _collWithdrawal argument.
    *
    * If both are positive, it will revert.
    */
    function _adjustPosition(
        uint _collWithdrawal,
        uint _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint _maxFeePercentage,
        uint256 _collDeposit
    )
        internal
        validMaxFeePercentageWhen(_maxFeePercentage, _isDebtIncrease)
        onlyActivePosition
    {
        LocalVariables_adjustPosition memory vars;

        if (_isDebtIncrease && _rChange == 0) {
            revert DebtIncreaseZeroDebtChange();
        }
        if (_collDeposit != 0 && _collWithdrawal != 0) {
            revert NotSingularCollateralChange();
        }
        if (_collDeposit == 0 && _collWithdrawal == 0 && _rChange == 0) {
            revert NoCollateralOrDebtChange();
        }

        _applyPendingRewards(msg.sender);

        // Get the collChange based on whether or not collateralToken was sent in the transaction
        (vars.collChange, vars.isCollIncrease) = _collDeposit != 0 ? (_collDeposit, true) : (_collWithdrawal, false);

        vars.netDebtChange = _rChange;

        // If the adjustment incorporates a debt increase, then trigger a borrowing fee
        if (_isDebtIncrease) {
            vars.rFee = _triggerBorrowingFee(rToken, _rChange, _maxFeePercentage);
            vars.netDebtChange += vars.rFee; // The raw debt change includes the fee
        }

        vars.debt = positions[msg.sender].debt;
        vars.coll = positions[msg.sender].coll;

        // Get the position's old ICR before the adjustment, and what its new ICR will be after the adjustment
        vars.price = priceFeed.fetchPrice();
        vars.oldICR = LiquityMath._computeCR(vars.coll, vars.debt, vars.price);
        vars.newICR = _getNewICRFromPositionChange(vars.coll, vars.debt, vars.collChange, vars.isCollIncrease, vars.netDebtChange, _isDebtIncrease, vars.price);
        assert(_collWithdrawal <= vars.coll);

        _requireICRisAboveMCR(vars.newICR);

        // When the adjustment is a debt repayment, check it's a valid amount and that the caller has enough R
        if (!_isDebtIncrease && _rChange > 0) {
            _requireAtLeastMinNetDebt(_getNetDebt(vars.debt) - vars.netDebtChange);
            _requireValidRRepayment(vars.debt, vars.netDebtChange);
            if (rToken.balanceOf(msg.sender) < vars.netDebtChange) {
                revert RepayNotEnoughR();
            }
        }

        positions[msg.sender].coll = vars.isCollIncrease ? vars.coll + vars.collChange : vars.coll - vars.collChange;
        positions[msg.sender].debt = _isDebtIncrease ? vars.debt + vars.netDebtChange : vars.debt - vars.netDebtChange;
        vars.stake = _updateStakeAndTotalStakes(msg.sender);

        // Re-insert position in to the sorted list
        vars.newNICR = _getNewNominalICRFromPositionChange(vars.coll, vars.debt, vars.collChange, vars.isCollIncrease, vars.netDebtChange, _isDebtIncrease);
        sortedPositions.reInsert(this, msg.sender, vars.newNICR, _upperHint, _lowerHint);

        emit PositionUpdated(msg.sender, positions[msg.sender].debt, positions[msg.sender].coll, vars.stake, PositionManagerOperation.adjustPosition);
        emit RBorrowingFeePaid(msg.sender, vars.rFee);

        // Use the unmodified _rChange here, as we don't send the fee to the user
        _moveTokensFromAdjustment(vars.collChange, vars.isCollIncrease, _rChange, _isDebtIncrease);
    }

    function closePosition() external override onlyActivePosition {
        _applyPendingRewards(msg.sender);

        uint coll = positions[msg.sender].coll;
        uint debt = positions[msg.sender].debt;

        if (rToken.balanceOf(msg.sender) < debt - R_GAS_COMPENSATION) {
            revert RepayNotEnoughR();
        }

        _removeStake(msg.sender);
        _closePosition(msg.sender, PositionStatus.closedByOwner);

        emit PositionUpdated(msg.sender, 0, 0, 0, PositionManagerOperation.closePosition);

        // Burn the repaid R from the user's balance and the gas compensation from the Gas Pool
        rToken.burn(msg.sender, debt - R_GAS_COMPENSATION);
        rToken.burn(address(this), R_GAS_COMPENSATION);

        // Send the collateral back to the user
        _activePoolCollateralBalance -= coll;
        collateralToken.transfer(msg.sender, coll);
    }

    // --- Position Liquidation functions ---

    // Single liquidation function. Closes the position if its ICR is lower than the minimum collateral ratio.
    function liquidate(address _borrower) external override {
        _requirePositionIsActive(_borrower);

        address[] memory borrowers = new address[](1);
        borrowers[0] = _borrower;
        batchLiquidatePositions(borrowers);
    }

    // --- Inner single liquidation functions ---

    // Liquidate one position
    function _liquidate(
        address _borrower,
        uint _ICR
    )
        internal
        returns (LiquidationValues memory singleLiquidation)
    {
        uint256 pendingCollReward;

        (singleLiquidation.entirePositionDebt, singleLiquidation.entirePositionColl,,pendingCollReward) 
            = getEntireDebtAndColl(_borrower);

        _movePendingPositionRewardsToActivePool(pendingCollReward);
        _removeStake(_borrower);

        singleLiquidation.collGasCompensation = _getCollGasCompensation(singleLiquidation.entirePositionColl);
        singleLiquidation.rGasCompensation = R_GAS_COMPENSATION;
        uint collToLiquidate = singleLiquidation.entirePositionColl - singleLiquidation.collGasCompensation;

        if (_ICR <= _100pct) {
            singleLiquidation.debtToOffset = 0;
            singleLiquidation.collToSendToLiquidator = 0;
            singleLiquidation.debtToRedistribute = singleLiquidation.entirePositionDebt;
            singleLiquidation.collToRedistribute = collToLiquidate;
        }
        else {
            singleLiquidation.debtToOffset = singleLiquidation.entirePositionDebt;
            singleLiquidation.collToSendToLiquidator = collToLiquidate;
            singleLiquidation.debtToRedistribute = 0;
            singleLiquidation.collToRedistribute = 0;
        }

        _closePosition(_borrower, PositionStatus.closedByLiquidation);
        emit PositionLiquidated(_borrower, singleLiquidation.entirePositionDebt, singleLiquidation.entirePositionColl, PositionManagerOperation.liquidate);
        emit PositionUpdated(_borrower, 0, 0, 0, PositionManagerOperation.liquidate);
        return singleLiquidation;
    }

    function _getTotalsFromLiquidatePositionsSequence
    (
        uint _price,
        uint _n
    )
        internal
        returns(LiquidationTotals memory totals)
    {
        for (uint256 i = 0; i < _n; ++i) {
            address user = sortedPositions.last;
            uint256 ICR = getCurrentICR(user, _price);

            if (ICR < MCR) {
                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, _liquidate(user, ICR));

            } else break;  // break if the loop reaches a Position with ICR >= MCR
        }
    }

    /*
    * Attempt to liquidate a custom list of positions provided by the caller.
    */
    function batchLiquidatePositions(address[] memory _positionArray) public override {
        if (_positionArray.length == 0) {
            revert PositionArrayEmpty();
        }

        // Perform the appropriate liquidation sequence - tally values and obtain their totals.
        LiquidationTotals memory totals = _getTotalsFromBatchLiquidate(priceFeed.fetchPrice(), _positionArray);

        if (totals.totalCollInSequence == 0) {
            revert NothingToLiquidate();
        }

        _offset(msg.sender, totals.totalDebtToOffset, totals.totalCollToSendToLiquidator);
        _redistributeDebtAndColl(totals.totalDebtToRedistribute, totals.totalCollToRedistribute);

        // Update system snapshots
        _updateSystemSnapshots_excludeCollRemainder(totals.totalCollGasCompensation);

        emit Liquidation(
            totals.totalDebtInSequence,
            totals.totalCollInSequence - totals.totalCollGasCompensation,
            totals.totalCollGasCompensation,
            totals.totalRGasCompensation
        );

        // Send gas compensation to caller
        _sendGasCompensation(msg.sender, totals.totalRGasCompensation, totals.totalCollGasCompensation);
    }

    function _offset(address liquidator, uint256 debtToBurn, uint256 collToSendToLiquidator) internal {
        if (debtToBurn == 0) { return; }

        rToken.burn(liquidator, debtToBurn);
        _activePoolCollateralBalance -= collToSendToLiquidator;
        collateralToken.transfer(liquidator, collToSendToLiquidator);
    }

    function _getTotalsFromBatchLiquidate
    (
        uint _price,
        address[] memory _positionArray
    )
        internal
        returns(LiquidationTotals memory totals)
    {
        uint256 _positionArrayLength = _positionArray.length;
        for (uint256 i = 0; i < _positionArrayLength; ++i) {
            address user = _positionArray[i];
            uint256 ICR = getCurrentICR(user, _price);

            if (ICR < MCR) {
                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, _liquidate(user, ICR));
            }
        }
    }

    // --- Liquidation helper functions ---

    function _addLiquidationValuesToTotals(LiquidationTotals memory oldTotals, LiquidationValues memory singleLiquidation)
    internal pure returns(LiquidationTotals memory newTotals) {

        // Tally all the values with their respective running totals
        newTotals.totalCollGasCompensation = oldTotals.totalCollGasCompensation + singleLiquidation.collGasCompensation;
        newTotals.totalRGasCompensation = oldTotals.totalRGasCompensation + singleLiquidation.rGasCompensation;
        newTotals.totalDebtInSequence = oldTotals.totalDebtInSequence + singleLiquidation.entirePositionDebt;
        newTotals.totalCollInSequence = oldTotals.totalCollInSequence + singleLiquidation.entirePositionColl;
        newTotals.totalDebtToOffset = oldTotals.totalDebtToOffset + singleLiquidation.debtToOffset;
        newTotals.totalCollToSendToLiquidator = oldTotals.totalCollToSendToLiquidator + singleLiquidation.collToSendToLiquidator;
        newTotals.totalDebtToRedistribute = oldTotals.totalDebtToRedistribute + singleLiquidation.debtToRedistribute;
        newTotals.totalCollToRedistribute = oldTotals.totalCollToRedistribute + singleLiquidation.collToRedistribute;

        return newTotals;
    }

    function _sendGasCompensation(address _liquidator, uint _R, uint _collateral) internal {
        if (_R > 0) {
            rToken.transfer(_liquidator, _R);
        }

        if (_collateral > 0) {
            _activePoolCollateralBalance -= _collateral;
            collateralToken.transfer(_liquidator, _collateral);
        }
    }

    // Move a Position's pending debt and collateral rewards from distributions, from the Default Pool to the Active Pool
    function _movePendingPositionRewardsToActivePool(uint _collateral) internal {
        _defaultPoolCollateralBalance -= _collateral;
        _activePoolCollateralBalance += _collateral;
    }

    // --- Redemption functions ---

    // Redeem as much collateral as possible from _borrower's Position in exchange for R up to _maxRamount
    function _redeemCollateralFromPosition(
        address _borrower,
        uint _maxRamount,
        uint _price,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint _partialRedemptionHintNICR
    )
        internal returns (SingleRedemptionValues memory singleRedemption)
    {
        // Determine the remaining amount (lot) to be redeemed, capped by the entire debt of the Position minus the liquidation reserve
        singleRedemption.rLot = Math.min(_maxRamount, positions[_borrower].debt - R_GAS_COMPENSATION);

        // Get the CollateralTokenLot of equivalent value in USD
        singleRedemption.collateralTokenLot = singleRedemption.rLot * DECIMAL_PRECISION / _price;

        // Decrease the debt and collateral of the current Position according to the R lot and corresponding collateralToken to send
        uint newDebt = positions[_borrower].debt - singleRedemption.rLot;
        uint newColl = positions[_borrower].coll - singleRedemption.collateralTokenLot;

        if (newDebt == R_GAS_COMPENSATION) {
            // No debt left in the Position (except for the liquidation reserve), therefore the position gets closed
            _removeStake(_borrower);
            _closePosition(_borrower, PositionStatus.closedByRedemption);
            _redeemClosePosition(_borrower, R_GAS_COMPENSATION, newColl);
            emit PositionUpdated(_borrower, 0, 0, 0, PositionManagerOperation.redeemCollateral);

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

            sortedPositions.reInsert(this, _borrower, newNICR, _upperPartialRedemptionHint, _lowerPartialRedemptionHint);

            positions[_borrower].debt = newDebt;
            positions[_borrower].coll = newColl;
            _updateStakeAndTotalStakes(_borrower);

            emit PositionUpdated(
                _borrower,
                newDebt, newColl,
                positions[_borrower].stake,
                PositionManagerOperation.redeemCollateral
            );
        }

        return singleRedemption;
    }

    /*
    * Called when a full redemption occurs, and closes the position.
    * The redeemer swaps (debt - liquidation reserve) R for (debt - liquidation reserve) worth of collateralToken, so the R liquidation reserve left corresponds to the remaining debt.
    * In order to close the position, the R liquidation reserve is burned, and the corresponding debt is removed from the active pool.
    * The debt recorded on the position's struct is zero'd elsewhere, in _closePosition.
    * Any surplus collateralToken left in the position, is sent to the Coll surplus pool, and can be later claimed by the borrower.
    */
    function _redeemClosePosition(address _borrower, uint _R, uint _collateral) internal {
        rToken.burn(address(this), _R);

        _activePoolCollateralBalance -= _collateral;
        collateralToken.transfer(_borrower, _collateral);
    }

    function _isValidFirstRedemptionHint(address _firstRedemptionHint, uint _price) internal view returns (bool) {
        if (_firstRedemptionHint == address(0) ||
            !sortedPositions.nodes[_firstRedemptionHint].exists ||
            getCurrentICR(_firstRedemptionHint, _price) < MCR
        ) {
            return false;
        }

        address nextPosition = sortedPositions.nodes[_firstRedemptionHint].nextId;
        return nextPosition == address(0) || getCurrentICR(nextPosition, _price) < MCR;
    }

    /* Send _rAmount R to the system and redeem the corresponding amount of collateral from as many Positions as are needed to fill the redemption
    * request.  Applies pending rewards to a Position before reducing its debt and coll.
    *
    * Note that if _amount is very large, this function can run out of gas, specially if traversed positions are small. This can be easily avoided by
    * splitting the total _amount in appropriate chunks and calling the function multiple times.
    *
    * Param `_maxIterations` can also be provided, so the loop through Positions is capped (if it’s zero, it will be ignored).This makes it easier to
    * avoid OOG for the frontend, as only knowing approximately the average cost of an iteration is enough, without needing to know the “topology”
    * of the position list. It also avoids the need to set the cap in stone in the contract, nor doing gas calculations, as both gas price and opcode
    * costs can vary.
    *
    * All Positions that are redeemed from -- with the likely exception of the last one -- will end up with no debt left, therefore they will be closed.
    * If the last Position does have some remaining debt, it has a finite ICR, and the reinsertion could be anywhere in the list, therefore it requires a hint.
    * A frontend should use getRedemptionHints() to calculate what the ICR of this Position will be after redemption, and pass a hint for its position
    * in the sortedPositions list along with the ICR value that the hint was found for.
    *
    * If another transaction modifies the list between calling getRedemptionHints() and passing the hints to redeemCollateral(), it
    * is very likely that the last (partially) redeemed Position would end up with a different ICR than what the hint is for. In this case the
    * redemption will stop after the last completely redeemed Position and the sender will keep the remaining R amount, which they can attempt
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
            revert PositionManagerMaxFeePercentageOutOfRange();
        }
        if (_rAmount == 0) {
            revert PositionManagerAmountIsZero();
        }
        if (rToken.balanceOf(msg.sender) < _rAmount) {
            revert PositionManagerRedemptionAmountExceedsBalance();
        }

        address currentBorrower;

        uint256 price = priceFeed.fetchPrice();
        if (_isValidFirstRedemptionHint(_firstRedemptionHint, price)) {
            currentBorrower = _firstRedemptionHint;
        } else {
            currentBorrower = sortedPositions.last;
            // Find the first position with ICR >= MCR
            while (currentBorrower != address(0) && getCurrentICR(currentBorrower, price) < MCR) {
                currentBorrower = sortedPositions.nodes[currentBorrower].prevId;
            }
        }

        uint256 remainingR = _rAmount;
        uint256 totalRToRedeem;
        uint256 totalCollateralTokenDrawn;
        // Loop through the Positions starting from the one with lowest collateral ratio until _amount of R is exchanged for collateral
        if (_maxIterations == 0) { _maxIterations = type(uint256).max; }
        while (currentBorrower != address(0) && remainingR > 0 && _maxIterations > 0) {
            _maxIterations--;
            // Save the address of the Position preceding the current one, before potentially modifying the list
            address nextUserToCheck = sortedPositions.nodes[currentBorrower].prevId;

            _applyPendingRewards(currentBorrower);

            SingleRedemptionValues memory singleRedemption = _redeemCollateralFromPosition(
                currentBorrower,
                remainingR,
                price,
                _upperPartialRedemptionHint,
                _lowerPartialRedemptionHint,
                _partialRedemptionHintNICR
            );

            if (singleRedemption.cancelledPartial) break; // Partial redemption was cancelled (out-of-date hint, or new net debt < minimum), therefore we could not redeem from the last Position

            totalRToRedeem += singleRedemption.rLot;
            totalCollateralTokenDrawn += singleRedemption.collateralTokenLot;

            remainingR -= singleRedemption.rLot;
            currentBorrower = nextUserToCheck;
        }

        if (totalCollateralTokenDrawn == 0) {
            revert UnableToRedeemAnyAmount();
        }

        // Decay the baseRate due to time passed, and then increase it according to the size of this redemption.
        // Use the saved total R supply value, from before it was reduced by the redemption.
        _updateBaseRateFromRedemption(totalCollateralTokenDrawn, price, rToken.totalSupply());

        // Calculate the collateralToken fee
        uint256 collateralTokenFee = _calcRedemptionFee(getRedemptionRate(), totalCollateralTokenDrawn);

        _requireUserAcceptsFee(collateralTokenFee, totalCollateralTokenDrawn, _maxFeePercentage);

        // Send the collateralToken fee to the recipient
        _activePoolCollateralBalance -= collateralTokenFee;
        collateralToken.transfer(feeRecipient, collateralTokenFee);

        emit Redemption(_rAmount, totalRToRedeem, totalCollateralTokenDrawn, collateralTokenFee);

        // Burn the total R that is cancelled with debt, and send the redeemed collateralToken to msg.sender
        rToken.burn(msg.sender, totalRToRedeem);

        // Send collateralToken to account
        uint256 collateralTokenToSendToRedeemer = totalCollateralTokenDrawn - collateralTokenFee;
        _activePoolCollateralBalance -= collateralTokenToSendToRedeemer;
        collateralToken.transfer(msg.sender, collateralTokenToSendToRedeemer);
    }

    // --- Helper functions ---

    // Return the nominal collateral ratio (ICR) of a given Position, without the price. Takes a position's pending coll and debt rewards from redistributions into account.
    function getNominalICR(address _borrower) public view override returns (uint nicr) {
        (uint currentCollateralToken, uint currentRDebt) = _getCurrentPositionAmounts(_borrower);

        nicr = LiquityMath._computeNominalCR(currentCollateralToken, currentRDebt);
    }

    // Return the current collateral ratio (ICR) of a given Position. Takes a position's pending coll and debt rewards from redistributions into account.
    function getCurrentICR(address _borrower, uint _price) public view override returns (uint icr) {
        (uint currentCollateralToken, uint currentRDebt) = _getCurrentPositionAmounts(_borrower);

        icr = LiquityMath._computeCR(currentCollateralToken, currentRDebt, _price);
    }

    function _getCurrentPositionAmounts(address _borrower) internal view returns (uint currentCollateralToken, uint currentRDebt) {
        currentCollateralToken = positions[_borrower].coll + getPendingCollateralTokenReward(_borrower);
        currentRDebt = positions[_borrower].debt + getPendingRDebtReward(_borrower);
    }

    // Add the borrowers's coll and debt rewards earned from redistributions, to their Position
    function _applyPendingRewards(address _borrower) internal {
        if (hasPendingRewards(_borrower)) {
            _requirePositionIsActive(_borrower);

            // Compute pending rewards
            uint pendingCollateralTokenReward = getPendingCollateralTokenReward(_borrower);
            uint pendingRDebtReward = getPendingRDebtReward(_borrower);

            // Apply pending rewards to position's state
            positions[_borrower].coll += pendingCollateralTokenReward;
            positions[_borrower].debt += pendingRDebtReward;

            _updatePositionRewardSnapshots(_borrower);

            // Transfer from DefaultPool to ActivePool
            _movePendingPositionRewardsToActivePool(pendingCollateralTokenReward);

            emit PositionUpdated(
                _borrower,
                positions[_borrower].debt,
                positions[_borrower].coll,
                positions[_borrower].stake,
                PositionManagerOperation.applyPendingRewards
            );
        }
    }

    // Update borrower's snapshots of L_CollateralBalance and L_RDebt to reflect the current values
    function _updatePositionRewardSnapshots(address _borrower) internal {
        rewardSnapshots[_borrower].collateralBalance = L_CollateralBalance;
        rewardSnapshots[_borrower].rDebt = L_RDebt;
        emit PositionSnapshotsUpdated(L_CollateralBalance, L_RDebt);
    }

    // Get the borrower's pending accumulated collateralToken reward, earned by their stake
    function getPendingCollateralTokenReward(address _borrower) public view override returns (uint pendingCollateralTokenReward) {
        uint snapshotCollateralBalance = rewardSnapshots[_borrower].collateralBalance;
        uint rewardPerUnitStaked = L_CollateralBalance - snapshotCollateralBalance;

        if (rewardPerUnitStaked == 0 || positions[_borrower].status != PositionStatus.active) { return 0; }

        pendingCollateralTokenReward = positions[_borrower].stake * rewardPerUnitStaked / DECIMAL_PRECISION;
    }

    // Get the borrower's pending accumulated R reward, earned by their stake
    function getPendingRDebtReward(address _borrower) public view override returns (uint pendingRDebtReward) {
        uint snapshotRDebt = rewardSnapshots[_borrower].rDebt;
        uint rewardPerUnitStaked = L_RDebt - snapshotRDebt;

        if (rewardPerUnitStaked == 0 || positions[_borrower].status != PositionStatus.active) { return 0; }

        pendingRDebtReward = positions[_borrower].stake * rewardPerUnitStaked / DECIMAL_PRECISION;
    }

    function hasPendingRewards(address _borrower) public view override returns (bool) {
        /*
        * A Position has pending rewards if its snapshot is less than the current rewards per-unit-staked sum:
        * this indicates that rewards have occured since the snapshot was made, and the user therefore has
        * pending rewards
        */
        return positions[_borrower].status == PositionStatus.active && rewardSnapshots[_borrower].collateralBalance < L_CollateralBalance;
    }

    // Return the Positions entire debt and coll, including pending rewards from redistributions.
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

        debt = positions[_borrower].debt + pendingRDebtReward;
        coll = positions[_borrower].coll + pendingCollateralTokenReward;
    }

    // Remove borrower's stake from the totalStakes sum, and set their stake to 0
    function _removeStake(address _borrower) internal {
        uint stake = positions[_borrower].stake;
        totalStakes = totalStakes - stake;
        positions[_borrower].stake = 0;
    }

    // Update borrower's stake based on their latest collateral value
    function _updateStakeAndTotalStakes(address _borrower) internal returns (uint newStake) {
        newStake = _computeNewStake(positions[_borrower].coll);
        uint oldStake = positions[_borrower].stake;
        positions[_borrower].stake = newStake;

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
            * - The system always contains >= 1 position
            * - When we close or liquidate a position, we redistribute the pending rewards, so if all positions were closed/liquidated,
            * rewards would’ve been emptied and totalCollateralSnapshot would be zero too.
            */
            assert(totalStakesSnapshot > 0);
            stake = _coll * totalStakesSnapshot / totalCollateralSnapshot;
        }
    }

    function _redistributeDebtAndColl(uint _debt, uint _coll) internal {
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

        // Transfer coll from ActivePool to DefaultPool
        _activePoolCollateralBalance -= _coll;
        _defaultPoolCollateralBalance += _coll;
    }

    function _closePosition(address _borrower, PositionStatus closedStatus) internal {
        assert(closedStatus != PositionStatus.nonExistent && closedStatus != PositionStatus.active);
        if (sortedPositions.size <= 1) {
            revert PositionManagerOnlyOnePositionInSystem();
        }

        positions[_borrower].status = closedStatus;
        positions[_borrower].coll = 0;
        positions[_borrower].debt = 0;

        rewardSnapshots[_borrower].collateralBalance = 0;
        rewardSnapshots[_borrower].rDebt = 0;

        sortedPositions.remove(_borrower);
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
    function _updateSystemSnapshots_excludeCollRemainder(uint _collRemainder) internal {
        totalStakesSnapshot = totalStakes;
        totalCollateralSnapshot = _activePoolCollateralBalance - _collRemainder + _defaultPoolCollateralBalance;

        emit SystemSnapshotsUpdated(totalStakesSnapshot, totalCollateralSnapshot);
    }

    // --- Redemption fee functions ---

    /*
    * This function has two impacts on the baseRate state variable:
    * 1) decays the baseRate based on time passed since last redemption or R borrowing operation.
    * then,
    * 2) increases the baseRate based on the amount redeemed, as a proportion of total supply
    */
    function _updateBaseRateFromRedemption(uint _collateralDrawn,  uint _price, uint _totalRSupply) internal returns (uint) {
        uint decayedBaseRate = _calcDecayedBaseRate();

        /* Convert the drawn collateralToken back to R at face value rate (1 R:1 USD), in order to get
        * the fraction of total supply that was redeemed at face value. */
        uint redeemedRFraction = _collateralDrawn * _price / _totalRSupply;

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

    function getRedemptionFeeWithDecay(uint _collateralDrawn) external view override returns (uint) {
        return _calcRedemptionFee(getRedemptionRateWithDecay(), _collateralDrawn);
    }

    function _calcRedemptionFee(uint _redemptionRate, uint _collateralDrawn) internal pure returns (uint redemptionFee) {
        redemptionFee = _redemptionRate * _collateralDrawn / DECIMAL_PRECISION;
        if (redemptionFee >= _collateralDrawn) {
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
        return _getBorrowingFee(_rDebt);
    }

     function _getBorrowingFee(uint _rDebt) internal view returns (uint) {
        return _calcBorrowingFee(getBorrowingRate(), _rDebt);
    }

    function getBorrowingFeeWithDecay(uint _rDebt) external view override returns (uint) {
        return _calcBorrowingFee(getBorrowingRateWithDecay(), _rDebt);
    }

    function _calcBorrowingFee(uint _borrowingRate, uint _rDebt) internal pure returns (uint) {
        return _borrowingRate * _rDebt / DECIMAL_PRECISION;
    }

    // Updates the baseRate state variable based on time elapsed since the last redemption or R borrowing operation.
    function _decayBaseRateFromBorrowing() internal {
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

        if (timePassed >= 1 minutes) {
            lastFeeOperationTime = block.timestamp;
            emit LastFeeOpTimeUpdated(block.timestamp);
        }
    }

    function _calcDecayedBaseRate() internal view returns (uint) {
        uint minutesPassed = (block.timestamp - lastFeeOperationTime) / 1 minutes;
        uint decayFactor = LiquityMath._decPow(MINUTE_DECAY_FACTOR, minutesPassed);

        return baseRate * decayFactor / DECIMAL_PRECISION;
    }

    // --- 'require' wrapper functions ---

    function _requirePositionIsActive(address _borrower) internal view {
        if (positions[_borrower].status != PositionStatus.active) {
            revert PositionManagerPositionNotActive();
        }
    }

    // --- Helper functions ---

    function _triggerBorrowingFee(IRToken _rToken, uint _rAmount, uint _maxFeePercentage) internal returns (uint rFee) {
        _decayBaseRateFromBorrowing(); // decay the baseRate state variable
        rFee = _getBorrowingFee(_rAmount);

        _requireUserAcceptsFee(rFee, _rAmount, _maxFeePercentage);

        if (rFee > 0) {
            _rToken.mint(feeRecipient, rFee);
        }
    }

    function _moveTokensFromAdjustment(uint _collChange, bool _isCollIncrease, uint _rChange, bool _isDebtIncrease)
        private
    {
        if (_isDebtIncrease) {
            rToken.mint(msg.sender, _rChange);
        } else {
            rToken.burn(msg.sender, _rChange);
        }

        if (_isCollIncrease) {
            _activePoolCollateralBalance += _collChange;
            collateralToken.transferFrom(msg.sender, address(this), _collChange);
        } else {
            _activePoolCollateralBalance -= _collChange;
            collateralToken.transfer(msg.sender, _collChange);
        }
    }

    // --- 'Require' wrapper functions ---

    function _requireICRisAboveMCR(uint _newICR) internal pure {
        if (_newICR < MCR) {
            revert NewICRLowerThanMCR(_newICR);
        }
    }

    function _requireAtLeastMinNetDebt(uint _netDebt) internal pure {
        if (_netDebt < MIN_NET_DEBT) {
            revert NetDebtBelowMinimum(_netDebt);
        }
    }

    function _requireValidRRepayment(uint _currentDebt, uint _debtRepayment) internal pure {
        if (_debtRepayment > _currentDebt - R_GAS_COMPENSATION) {
            revert RepayRAmountExceedsDebt(_debtRepayment);
        }
    }

    // --- ICR getters ---

    // Compute the new collateral ratio, considering the change in coll and debt. Assumes 0 pending rewards.
    function _getNewNominalICRFromPositionChange
    (
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease
    )
        pure
        internal
        returns (uint newNICR)
    {
        (uint newColl, uint newDebt) = _getNewPositionAmounts(_coll, _debt, _collChange, _isCollIncrease, _debtChange, _isDebtIncrease);

        newNICR = LiquityMath._computeNominalCR(newColl, newDebt);
    }

    // Compute the new collateral ratio, considering the change in coll and debt. Assumes 0 pending rewards.
    function _getNewICRFromPositionChange
    (
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease,
        uint _price
    )
        pure
        internal
        returns (uint newICR)
    {
        (uint newColl, uint newDebt) = _getNewPositionAmounts(_coll, _debt, _collChange, _isCollIncrease, _debtChange, _isDebtIncrease);

        newICR = LiquityMath._computeCR(newColl, newDebt, _price);
    }

    function _getNewPositionAmounts(
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease
    )
        internal
        pure
        returns (uint newColl, uint newDebt)
    {
        newColl = _isCollIncrease ? _coll + _collChange :  _coll - _collChange;
        newDebt = _isDebtIncrease ? _debt + _debtChange : _debt - _debtChange;
    }

    function getCompositeDebt(uint _debt) external pure override returns (uint) {
        return _getCompositeDebt(_debt);
    }

    function sortedPositionsNodes(address _id) external view override returns(bool exists, address nextId, address prevId) {
        return (sortedPositions.nodes[_id].exists, sortedPositions.nodes[_id].nextId, sortedPositions.nodes[_id].prevId);
    }
}
