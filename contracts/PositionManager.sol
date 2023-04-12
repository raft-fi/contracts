// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./Dependencies/MathUtils.sol";
import "./Interfaces/IPositionManager.sol";
import "./FeeCollector.sol";
import "./SortedPositions.sol";
import "./RToken.sol";
import "./ERC20Indexable.sol";

contract PositionManager is FeeCollector, IPositionManager {
    using SortedPositions for SortedPositions.Data;
    using Fixed256x18 for uint256;

    // --- Connected contract declarations ---

    IERC20 public immutable override collateralToken;
    IRToken public immutable override rToken;
    IPriceFeed public immutable override priceFeed;

    IERC20Indexable public immutable override raftDebtToken;
    IERC20Indexable public immutable override raftCollateralToken;
    mapping(address delegate => bool isWhitelisted) public override globalDelegateWhitelist;
    mapping(address borrower => mapping(address delegate => bool isWhitelisted)) public override individualDelegateWhitelist;

    uint256 public override liquidationProtocolFee;

    // A doubly linked list of Positions, sorted by their sorted by their collateral ratios
    SortedPositions.Data public override sortedPositions;

    /*
     * Half-life of 12h. 12h = 720 min
     * (1/2) = d^720 => d = (1/2)^(1/720)
     */
    uint256 public constant MINUTE_DECAY_FACTOR = 999037758833783000;
    uint256 public constant REDEMPTION_FEE_FLOOR = MathUtils.DECIMAL_PRECISION / 1000 * 5; // 0.5%
    uint256 public constant override MAX_BORROWING_SPREAD = MathUtils.DECIMAL_PRECISION / 100; // 1%
    uint256 public constant MAX_BORROWING_FEE = MathUtils.DECIMAL_PRECISION / 100 * 5; // 5%
    uint256 public constant override MAX_LIQUIDATION_PROTOCOL_FEE = MathUtils.DECIMAL_PRECISION / 100 * 80; // 80%

    /*
    * BETA: 18 digit decimal. Parameter by which to divide the redeemed fraction, in order to calc the new base rate from a redemption.
    * Corresponds to (1 / ALPHA) in the white paper.
    */
    uint256 public constant BETA = 2;

    uint256 public override borrowingSpread;
    uint256 public baseRate;

    // The timestamp of the latest fee operation (redemption or new R issuance)
    uint256 public lastFeeOperationTime;

    uint256 private totalDebt;

    modifier validMaxFeePercentageWhen(uint256 _maxFeePercentage, bool condition) {
        if (condition && (_maxFeePercentage < borrowingSpread || _maxFeePercentage > MathUtils.DECIMAL_PRECISION)) {
            revert PositionManagerInvalidMaxFeePercentage();
        }
        _;
    }

    modifier onlyActivePosition(address _borrower) {
        if (!sortedPositions.nodes[_borrower].exists) {
            revert PositionManagerPositionNotActive();
        }
        _;
    }

    // --- Constructor ---

    constructor(
        IPriceFeed _priceFeed,
        IERC20 _collateralToken,
        uint256 _positionsSize,
        uint256 _liquidationProtocolFee,
        address[] memory delegates
    ) FeeCollector(msg.sender) {
        priceFeed = _priceFeed;
        collateralToken = _collateralToken;
        rToken = new RToken(address(this), msg.sender);
        raftCollateralToken = new ERC20Indexable(
            address(this),
            string(bytes.concat("Raft ", bytes(IERC20Metadata(address(_collateralToken)).name()), " collateral")),
            string(bytes.concat("r", bytes(IERC20Metadata(address(_collateralToken)).symbol()), "-c"))
        );
        raftDebtToken = new ERC20Indexable(
            address(this),
            string(bytes.concat("Raft ", bytes(IERC20Metadata(address(rToken)).name()), " debt")),
            string(bytes.concat("r", bytes(IERC20Metadata(address(rToken)).symbol()), "-d"))
        );
        sortedPositions.maxSize = _positionsSize;
        setLiquidationProtocolFee(_liquidationProtocolFee);
        for (uint256 i = 0; i < delegates.length; ++i) {
            if (delegates[i] == address(0)) {
                revert InvalidDelegateAddress();
            }
            globalDelegateWhitelist[delegates[i]] = true;
        }

        emit PositionManagerDeployed(_priceFeed, _collateralToken, rToken, raftCollateralToken, raftDebtToken, msg.sender);
    }

    function setLiquidationProtocolFee(uint256 _liquidationProtocolFee) public override onlyOwner {
        if (_liquidationProtocolFee > MAX_LIQUIDATION_PROTOCOL_FEE) {
            revert LiquidationProtocolFeeOutOfBound();
        }

        liquidationProtocolFee = _liquidationProtocolFee;
        emit LiquidationProtocolFeeChanged(_liquidationProtocolFee);
    }

    function managePosition(
        address _borrower,
        uint256 _collChange,
        bool _isCollIncrease,
        uint256 _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external override {
        _managePosition(
            _borrower,
            _collChange,
            _isCollIncrease,
            _rChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _maxFeePercentage,
            true
        );
    }

    function managePosition(
        uint256 _collChange,
        bool _isCollIncrease,
        uint256 _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external override {
        _managePosition(
            msg.sender,
            _collChange,
            _isCollIncrease,
            _rChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _maxFeePercentage,
            true
        );
    }

    function _managePosition(
        address _borrower,
        uint256 _collChange,
        bool _isCollIncrease,
        uint256 _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage,
        bool _needsCollateralTransfer
    )
        internal
        validMaxFeePercentageWhen(_maxFeePercentage, _isDebtIncrease)
    {
        if (
            _borrower != msg.sender && !globalDelegateWhitelist[msg.sender]
                && !individualDelegateWhitelist[_borrower][msg.sender]
        ) {
            revert DelegateNotWhitelisted();
        }
        if (_collChange == 0 && _rChange == 0) {
            revert NoCollateralOrDebtChange();
        }
        bool newPosition = !sortedPositions.nodes[_borrower].exists;
        _adjustDebt(_borrower, _rChange, _isDebtIncrease, _maxFeePercentage, newPosition);
        _adjustCollateral(_borrower, _collChange, _isCollIncrease, _needsCollateralTransfer);

        if (raftDebtToken.balanceOf(_borrower) == 0) {
            // position was closed, remove it
            _removePositionFromSortedPositions(_borrower);

        } else {
            checkValidPosition(_borrower);
            sortedPositions.update(
                this,
                _borrower,
                getNominalICR(_borrower),
                _upperHint,
                _lowerHint
            );
            if (newPosition) {
                emit PositionCreated(_borrower);
            }
        }
    }

    function _adjustDebt(address _borrower, uint256 _rChange, bool _isDebtIncrease, uint256 _maxFeePercentage, bool _newPosition) internal {
        if (_rChange == 0) {
            return;
        }

        if (_isDebtIncrease) {
            uint256 debtChange = _rChange + _triggerBorrowingFee(_borrower,_rChange, _maxFeePercentage);
            if (_newPosition) {
                // New position is created here, so we need to add gas compensation
                debtChange += MathUtils.R_GAS_COMPENSATION;
                rToken.mint(address(this), MathUtils.R_GAS_COMPENSATION);
            }
            raftDebtToken.mint(_borrower, debtChange);
            totalDebt += debtChange;
            rToken.mint(_borrower, _rChange);
        }
        else {
            uint256 positionsDebt = raftDebtToken.balanceOf(_borrower);
            uint256 netDebt = MathUtils.getNetDebt(positionsDebt);
            uint256 debtToBurn = _rChange;
            if (netDebt == _rChange) {
                debtToBurn += MathUtils.R_GAS_COMPENSATION;
                rToken.burn(address(this), MathUtils.R_GAS_COMPENSATION);
            }
            totalDebt -= debtToBurn;
            raftDebtToken.burn(_borrower, debtToBurn);
            rToken.burn(_borrower, _rChange);
        }

        emit DebtChanged(_borrower, _rChange, _isDebtIncrease);
    }

    function _adjustCollateral(address _borrower, uint256 _collChange, bool _isCollIncrease, bool _needsCollTransfer) internal {
        if (_collChange == 0) {
            return;
        }

        if (_isCollIncrease) {
            raftCollateralToken.mint(_borrower, _collChange);
            if (_needsCollTransfer) {
                collateralToken.transferFrom(msg.sender, address(this), _collChange);
            }
        } else {
            raftCollateralToken.burn(_borrower, _collChange);
            if (_needsCollTransfer) {
                collateralToken.transfer(_borrower, _collChange);
            }
        }

        emit CollateralChanged(_borrower, _collChange, _isCollIncrease);
    }

    function whitelistDelegate(address delegate) external override {
        if (delegate == address(0)) {
            revert InvalidDelegateAddress();
        }
        individualDelegateWhitelist[msg.sender][delegate] = true;
    }

    // --- Position Liquidation functions ---

    // Single liquidation function. Closes the position if its ICR is lower than the minimum collateral ratio.
    function liquidate(address _borrower) external override onlyActivePosition(_borrower) {
        address[] memory borrowers = new address[](1);
        borrowers[0] = _borrower;
        batchLiquidatePositions(borrowers);
    }

    // --- Inner single liquidation functions ---

    // Liquidate one position
    function _liquidate(LiquidationTotals memory oldLiquidationTotals, address _borrower, uint256 _ICR, uint256 _price)
        internal
        returns (LiquidationTotals memory newLiquidationTotals)
    {
        newLiquidationTotals = increaseLiquidationTotals(oldLiquidationTotals, _borrower, _ICR, _price);

        _removePositionFromSortedPositions(_borrower);
        raftDebtToken.burn(_borrower, type(uint256).max);
        raftCollateralToken.burn(_borrower, type(uint256).max);
        
        emit PositionLiquidated(_borrower);
    }

    function increaseLiquidationTotals(
        LiquidationTotals memory oldLiquidationTotals,
        address borrower,
        uint256 icr,
        uint256 price
    ) 
        internal view returns (LiquidationTotals memory)
    {
        uint256 entirePositionDebt = raftDebtToken.balanceOf(borrower);
        uint256 entirePositionColl = raftCollateralToken.balanceOf(borrower);

        oldLiquidationTotals.rGasCompensation += MathUtils.R_GAS_COMPENSATION;
        if (icr <= MathUtils._100pct) {
            // redistribution
            uint256 collGasCompensation = MathUtils.getCollGasCompensation(entirePositionColl);
            oldLiquidationTotals.collGasCompensation += collGasCompensation;
            oldLiquidationTotals.debtToRedistribute += entirePositionDebt;
            oldLiquidationTotals.collToRedistribute += entirePositionColl - collGasCompensation;
        } else {
            // offset
            uint256 collToSendToProtocol = _getCollLiquidationProtocolFee(
                entirePositionColl, entirePositionDebt, price, liquidationProtocolFee
            );
            oldLiquidationTotals.debtToOffset += entirePositionDebt;
            oldLiquidationTotals.collToSendToProtocol += collToSendToProtocol;
            oldLiquidationTotals.collToSendToLiquidator += entirePositionColl - collToSendToProtocol;
        }

        return (oldLiquidationTotals);
    }

    function simulateBatchLiquidatePositions(address[] memory _positionArray, uint256 _price)
        external
        view
        override
        returns (LiquidationTotals memory totals)
    {
        uint256 _positionArrayLength = _positionArray.length;
        for (uint256 i = 0; i < _positionArrayLength; ++i) {
            address user = _positionArray[i];
            uint256 ICR = getCurrentICR(user, _price);

            if (ICR < MathUtils.MCR) {
                // Add liquidation values to their respective running totals
                totals = increaseLiquidationTotals(totals, user, ICR, _price);
            }
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
        LiquidationTotals memory totals = _batchLiquidate(_positionArray);

        if (totals.collGasCompensation + totals.collToRedistribute + totals.collToSendToLiquidator == 0) {
            revert NothingToLiquidate();
        }

        // First send gas compenstion to user, this will require less capital from liquidator beforehand
        _sendGasCompensation(msg.sender, totals.rGasCompensation, totals.collGasCompensation);

        _offset(msg.sender, totals.debtToOffset, totals.collToSendToProtocol, totals.collToSendToLiquidator);
        updateDebtAndCollIndex();

        emit Liquidation(
            msg.sender,
            totals.collGasCompensation,
            totals.rGasCompensation,
            totals.debtToOffset,
            totals.collToSendToProtocol,
            totals.collToSendToLiquidator,
            totals.debtToRedistribute,
            totals.collToRedistribute
        );
    }

    function _offset(
        address liquidator,
        uint256 debtToBurn,
        uint256 collToSendToProtocol,
        uint256 collToSendToLiquidator
    ) internal {
        if (debtToBurn == 0) return;

        rToken.burn(liquidator, debtToBurn);
        totalDebt -= debtToBurn;
        collateralToken.transfer(liquidator, collToSendToLiquidator);
        collateralToken.transfer(feeRecipient, collToSendToProtocol);
    }

    function _batchLiquidate(address[] memory _positionArray) internal returns (LiquidationTotals memory totals) {
        uint256 price = priceFeed.fetchPrice();
        uint256 _positionArrayLength = _positionArray.length;
        for (uint256 i = 0; i < _positionArrayLength; ++i) {
            address user = _positionArray[i];
            uint256 ICR = getCurrentICR(user, price);

            if (ICR < MathUtils.MCR) {
                // Add liquidation values to their respective running totals
                totals = _liquidate(totals, user, ICR, price);
            }
        }
    }

    // --- Liquidation helper functions ---
    function _sendGasCompensation(address _liquidator, uint256 _R, uint256 _collateral) internal {
        if (_R > 0) {
            rToken.transfer(_liquidator, _R);
        }

        if (_collateral > 0) {
            collateralToken.transfer(_liquidator, _collateral);
        }
    }

    // --- Redemption functions ---

    // Redeem as much collateral as possible from _borrower's Position in exchange for R up to _maxRamount
    function _redeemCollateralFromPosition(
        address _borrower,
        uint256 _maxRamount,
        uint256 _price,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint256 _partialRedemptionHintNICR
    )
        internal returns (uint256 rLot)
    {
        uint256 positionDebt = raftDebtToken.balanceOf(_borrower);
        // Determine the remaining amount (lot) to be redeemed, capped by the entire debt of the Position minus the liquidation reserve
        rLot = Math.min(_maxRamount, positionDebt - MathUtils.R_GAS_COMPENSATION);
        uint256 collateralToRedeem = rLot * MathUtils.DECIMAL_PRECISION / _price;

        // Decrease the debt and collateral of the current Position according to the R lot and corresponding collateralToken to send
        uint256 newDebt = positionDebt - rLot;
        uint256 newColl = raftCollateralToken.balanceOf(_borrower) - collateralToRedeem;


        if (newDebt == MathUtils.R_GAS_COMPENSATION) {
            // No debt left in the Position (except for the liquidation reserve), therefore the position gets closed
            _removePositionFromSortedPositions(_borrower);
            raftDebtToken.burn(_borrower, type(uint256).max);
            raftCollateralToken.burn(_borrower, type(uint256).max);
            
            rToken.burn(address(this), MathUtils.R_GAS_COMPENSATION);
            totalDebt -= MathUtils.R_GAS_COMPENSATION;
            collateralToken.transfer(_borrower, newColl);
        } else {
            uint256 newNICR = MathUtils.computeNominalCR(newColl, newDebt);

            /*
            * If the provided hint is out of date, we bail since trying to reinsert without a good hint will almost
            * certainly result in running out of gas.
            *
            * If the resultant net debt of the partial is less than the minimum, net debt we bail.
            */
            if (newNICR != _partialRedemptionHintNICR || MathUtils.getNetDebt(newDebt) < MathUtils.MIN_NET_DEBT) {
                rLot = 0;
            } else {
                sortedPositions.update(
                    this, _borrower, newNICR, _upperPartialRedemptionHint, _lowerPartialRedemptionHint
                );

                raftDebtToken.burn(_borrower, rLot);
                raftCollateralToken.burn(_borrower, collateralToRedeem);
            }
        }
    }

    function _isValidFirstRedemptionHint(address _firstRedemptionHint, uint256 _price) internal view returns (bool) {
        if (
            _firstRedemptionHint == address(0) || !sortedPositions.nodes[_firstRedemptionHint].exists
                || getCurrentICR(_firstRedemptionHint, _price) < MathUtils.MCR
        ) {
            return false;
        }

        address nextPosition = sortedPositions.nodes[_firstRedemptionHint].nextId;
        return nextPosition == address(0) || getCurrentICR(nextPosition, _price) < MathUtils.MCR;
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
        uint256 _rAmount,
        address _firstRedemptionHint,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint256 _partialRedemptionHintNICR,
        uint256 _maxIterations,
        uint256 _maxFeePercentage
    ) external override {
        if (_maxFeePercentage < REDEMPTION_FEE_FLOOR || _maxFeePercentage > MathUtils.DECIMAL_PRECISION) {
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
            // Find the first position with ICR >= MathUtils.MCR
            while (currentBorrower != address(0) && getCurrentICR(currentBorrower, price) < MathUtils.MCR) {
                currentBorrower = sortedPositions.nodes[currentBorrower].prevId;
            }
        }

        uint256 remainingR = _rAmount;
        // Loop through the Positions starting from the one with lowest collateral ratio until _amount of R is exchanged for collateral
        if (_maxIterations == 0) _maxIterations = type(uint256).max;
        while (currentBorrower != address(0) && remainingR > 0 && _maxIterations > 0) {
            _maxIterations--;
            // Save the address of the Position preceding the current one, before potentially modifying the list
            address nextUserToCheck = sortedPositions.nodes[currentBorrower].prevId;

            uint256 rLot = _redeemCollateralFromPosition(
                currentBorrower,
                remainingR,
                price,
                _upperPartialRedemptionHint,
                _lowerPartialRedemptionHint,
                _partialRedemptionHintNICR
            );

            if (rLot == 0) break; // Partial redemption was cancelled (out-of-date hint, or new net debt < minimum), therefore we could not redeem from the last Position

            remainingR -= rLot;
            currentBorrower = nextUserToCheck;
        }
        uint256 totalRRedeemed = _rAmount - remainingR;
        uint256 totalCollateralTokenDrawn = totalRRedeemed * MathUtils.DECIMAL_PRECISION / price;

        if (totalCollateralTokenDrawn == 0) {
            revert UnableToRedeemAnyAmount();
        }

        // Decay the baseRate due to time passed, and then increase it according to the size of this redemption.
        // Use the saved total R supply value, from before it was reduced by the redemption.
        _updateBaseRateFromRedemption(totalCollateralTokenDrawn, price, rToken.totalSupply());

        // Calculate the collateralToken fee
        uint256 collateralTokenFee = _calcRedemptionFee(getRedemptionRate(), totalCollateralTokenDrawn);

        MathUtils.checkIfValidFee(collateralTokenFee, totalCollateralTokenDrawn, _maxFeePercentage);

        // Send the collateralToken fee to the recipient
        collateralToken.transfer(feeRecipient, collateralTokenFee);

        emit Redemption(_rAmount, totalRRedeemed, totalCollateralTokenDrawn, collateralTokenFee);

        // Burn the total R that is cancelled with debt, and send the redeemed collateralToken to msg.sender
        rToken.burn(msg.sender, totalRRedeemed);
        totalDebt -= totalRRedeemed;

        // Send collateralToken to account
        uint256 collateralTokenToSendToRedeemer = totalCollateralTokenDrawn - collateralTokenFee;
        collateralToken.transfer(msg.sender, collateralTokenToSendToRedeemer);
    }

    // --- Helper functions ---

    // Return the nominal collateral ratio (ICR) of a given Position, without the price. Takes a position's pending coll and debt rewards from redistributions into account.
    function getNominalICR(address borrower) public view override returns (uint256 nicr) {
        return MathUtils.computeNominalCR(
            raftCollateralToken.balanceOf(borrower),
            raftDebtToken.balanceOf(borrower)
        );
    }

    // Return the current collateral ratio (ICR) of a given Position. Takes a position's pending coll and debt rewards from redistributions into account.
    function getCurrentICR(address borrower, uint256 price) public view override returns (uint256) {
        return MathUtils.computeCR(
            raftCollateralToken.balanceOf(borrower),
            raftDebtToken.balanceOf(borrower),
            price
        );
    }

    function updateDebtAndCollIndex() internal {
        raftDebtToken.setIndex(totalDebt);
        raftCollateralToken.setIndex(collateralToken.balanceOf(address(this)));
    }

    function _removePositionFromSortedPositions(address _borrower) internal {
        if (sortedPositions.size <= 1) {
            revert PositionManagerOnlyOnePositionInSystem();
        }
        sortedPositions.remove(_borrower);
        emit PositionClosed(_borrower);
    }

    // --- Redemption fee functions ---

    /*
    * This function has two impacts on the baseRate state variable:
    * 1) decays the baseRate based on time passed since last redemption or R borrowing operation.
    * then,
    * 2) increases the baseRate based on the amount redeemed, as a proportion of total supply
    */
    function _updateBaseRateFromRedemption(uint256 _collateralDrawn, uint256 _price, uint256 _totalRSupply)
        internal
        returns (uint256)
    {
        uint256 decayedBaseRate = _calcDecayedBaseRate();

        /* Convert the drawn collateralToken back to R at face value rate (1 R:1 USD), in order to get
        * the fraction of total supply that was redeemed at face value. */
        uint256 redeemedRFraction = _collateralDrawn * _price / _totalRSupply;

        uint256 newBaseRate = decayedBaseRate + redeemedRFraction / BETA;
        newBaseRate = Math.min(newBaseRate, MathUtils.DECIMAL_PRECISION); // cap baseRate at a maximum of 100%
        //assert(newBaseRate <= MathUtils.DECIMAL_PRECISION); // This is already enforced in the line above
        assert(newBaseRate > 0); // Base rate is always non-zero after redemption

        // Update the baseRate state variable
        baseRate = newBaseRate;
        emit BaseRateUpdated(newBaseRate);

        _updateLastFeeOpTime();

        return newBaseRate;
    }

    function getRedemptionRate() public view override returns (uint256) {
        return _calcRedemptionRate(baseRate);
    }

    function getRedemptionRateWithDecay() public view override returns (uint256) {
        return _calcRedemptionRate(_calcDecayedBaseRate());
    }

    function _calcRedemptionRate(uint256 _baseRate) internal pure returns (uint256) {
        return Math.min(
            REDEMPTION_FEE_FLOOR + _baseRate,
            MathUtils.DECIMAL_PRECISION // cap at a maximum of 100%
        );
    }

    function getRedemptionFeeWithDecay(uint256 _collateralDrawn) external view override returns (uint256) {
        return _calcRedemptionFee(getRedemptionRateWithDecay(), _collateralDrawn);
    }

    function _calcRedemptionFee(uint256 _redemptionRate, uint256 _collateralDrawn)
        internal
        pure
        returns (uint256 redemptionFee)
    {
        redemptionFee = _redemptionRate * _collateralDrawn / MathUtils.DECIMAL_PRECISION;
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

    function getBorrowingRate() public view override returns (uint256) {
        return _calcBorrowingRate(baseRate);
    }

    function getBorrowingRateWithDecay() public view override returns (uint256) {
        return _calcBorrowingRate(_calcDecayedBaseRate());
    }

    function _calcBorrowingRate(uint256 _baseRate) internal view returns (uint256) {
        return Math.min(borrowingSpread + _baseRate, MAX_BORROWING_FEE);
    }

    function getBorrowingFee(uint256 _rDebt) external view override returns (uint256) {
        return _getBorrowingFee(_rDebt);
    }

    function _getBorrowingFee(uint256 _rDebt) internal view returns (uint256) {
        return _calcBorrowingFee(getBorrowingRate(), _rDebt);
    }

    function getBorrowingFeeWithDecay(uint256 _rDebt) external view override returns (uint256) {
        return _calcBorrowingFee(getBorrowingRateWithDecay(), _rDebt);
    }

    function _calcBorrowingFee(uint256 _borrowingRate, uint256 _rDebt) internal pure returns (uint256) {
        return _borrowingRate * _rDebt / MathUtils.DECIMAL_PRECISION;
    }

    // Updates the baseRate state variable based on time elapsed since the last redemption or R borrowing operation.
    function _decayBaseRateFromBorrowing() internal {
        uint256 decayedBaseRate = _calcDecayedBaseRate();
        assert(decayedBaseRate <= MathUtils.DECIMAL_PRECISION); // The baseRate can decay to 0

        baseRate = decayedBaseRate;
        emit BaseRateUpdated(decayedBaseRate);

        _updateLastFeeOpTime();
    }

    // --- Internal fee functions ---

    // Update the last fee operation time only if time passed >= decay interval. This prevents base rate griefing.
    function _updateLastFeeOpTime() internal {
        uint256 timePassed = block.timestamp - lastFeeOperationTime;

        if (timePassed >= 1 minutes) {
            lastFeeOperationTime = block.timestamp;
            emit LastFeeOpTimeUpdated(block.timestamp);
        }
    }

    function _calcDecayedBaseRate() internal view returns (uint256) {
        uint256 minutesPassed = (block.timestamp - lastFeeOperationTime) / 1 minutes;
        uint256 decayFactor = MathUtils.decPow(MINUTE_DECAY_FACTOR, minutesPassed);

        return baseRate * decayFactor / MathUtils.DECIMAL_PRECISION;
    }

    /// ---- Liquidation fee functions ---

    function _getCollLiquidationProtocolFee(uint256 _entireColl, uint256 _entireDebt, uint256 _price, uint256 _fee)
        internal
        pure
        returns (uint256)
    {
        assert(_fee <= MathUtils.DECIMAL_PRECISION);

        // the value of the position's debt, denominated in collateral token
        uint256 debtValue = _entireDebt * MathUtils.DECIMAL_PRECISION / _price;
        uint256 excessCollateral = _entireColl - debtValue;

        return excessCollateral * _fee / MathUtils.DECIMAL_PRECISION;
    }

    // --- Helper functions ---

    function _triggerBorrowingFee(address _borrower, uint256 _rAmount, uint256 _maxFeePercentage) internal returns (uint256 rFee) {
        _decayBaseRateFromBorrowing(); // decay the baseRate state variable
        rFee = _getBorrowingFee(_rAmount);

        MathUtils.checkIfValidFee(rFee, _rAmount, _maxFeePercentage);

        if (rFee > 0) {
            rToken.mint(feeRecipient, rFee);
            emit RBorrowingFeePaid(_borrower, rFee);
        }
    }

    // --- 'Require' wrapper functions ---

    function checkValidPosition(address position) internal {
        uint256 netDebt = MathUtils.getNetDebt(raftDebtToken.balanceOf(position));
        if (netDebt < MathUtils.MIN_NET_DEBT) {
            revert NetDebtBelowMinimum(netDebt);
        }
        
        uint256 newICR = getCurrentICR(position, priceFeed.fetchPrice());
        if (newICR < MathUtils.MCR) {
            revert NewICRLowerThanMCR(newICR);
        }
    }

    function sortedPositionsNodes(address _id) external view override returns(bool exists, address nextId, address prevId) {
        return (sortedPositions.nodes[_id].exists, sortedPositions.nodes[_id].nextId, sortedPositions.nodes[_id].prevId);
    }
}
