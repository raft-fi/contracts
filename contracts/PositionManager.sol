// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Fixed256x18} from "@tempus-labs/contracts/math/Fixed256x18.sol";
import {MathUtils} from "./Dependencies/MathUtils.sol";
import {IERC20Indexable} from "./Interfaces/IERC20Indexable.sol";
import {IPositionManager} from "./Interfaces/IPositionManager.sol";
import {IPriceFeed} from "./Interfaces/IPriceFeed.sol";
import {FeeCollector} from "./FeeCollector.sol";
import {SortedPositions} from "./SortedPositions.sol";
import {RToken, IRToken} from "./RToken.sol";
import {ERC20Indexable} from "./ERC20Indexable.sol";

contract PositionManager is FeeCollector, IPositionManager {
    using SafeERC20 for IERC20;
    using SortedPositions for SortedPositions.Data;
    using Fixed256x18 for uint256;

    // --- Connected contract declarations ---

    IRToken public immutable override rToken;

    IERC20Indexable public immutable override raftDebtToken;

    mapping(IERC20 collateralToken => IERC20Indexable raftCollateralToken) public override raftCollateralTokens;

    mapping(IERC20 collateralToken => IPriceFeed priceFeed) public override priceFeeds;

    mapping(address borrower => IERC20 collateralToken) public override collateralTokenPerBorrowers;

    mapping(address delegate => bool isWhitelisted) public override globalDelegateWhitelist;
    mapping(address borrower => mapping(address delegate => bool isWhitelisted)) public override
        individualDelegateWhitelist;

    uint256 public override liquidationProtocolFee;
    uint256 public override minDebt;

    mapping(IERC20 collateralToken => SortedPositions.Data data) public override sortedPositions;

    /*
     * Half-life of 12h. 12h = 720 min
     * (1/2) = d^720 => d = (1/2)^(1/720)
     */
    uint256 public constant MINUTE_DECAY_FACTOR = 999_037_758_833_783_000;
    uint256 public constant REDEMPTION_FEE_FLOOR = MathUtils._100_PERCENT / 1000 * 5; // 0.5%
    uint256 public constant override MAX_BORROWING_SPREAD = MathUtils._100_PERCENT / 100; // 1%
    uint256 public constant MAX_BORROWING_FEE = MathUtils._100_PERCENT / 100 * 5; // 5%
    uint256 public constant override MAX_LIQUIDATION_PROTOCOL_FEE = MathUtils._100_PERCENT / 100 * 80; // 80%

    /*
    * BETA: 18 digit decimal. Parameter by which to divide the redeemed fraction, in order to calc the new base rate
    from a redemption.
    * Corresponds to (1 / ALPHA) in the white paper.
    */
    uint256 public constant BETA = 2;

    uint256 public override borrowingSpread;
    uint256 public baseRate;

    // The timestamp of the latest fee operation (redemption or new R issuance)
    uint256 public lastFeeOperationTime;

    uint256 private totalDebt;

    modifier collateralTokenExists(IERC20 _collateralToken) {
        if (address(raftCollateralTokens[_collateralToken]) == address(0)) {
            revert CollateralTokenNotAdded();
        }
        _;
    }

    modifier onlyDepositedCollateralTokenOrNew(address _borrower, IERC20 _collateralToken) {
        if (
            collateralTokenPerBorrowers[_borrower] != IERC20(address(0))
                && collateralTokenPerBorrowers[_borrower] != _collateralToken
        ) {
            revert BorrowerHasDifferentCollateralToken();
        }
        _;
    }

    modifier validMaxFeePercentageWhen(uint256 _maxFeePercentage, bool condition) {
        if (condition && (_maxFeePercentage < borrowingSpread || _maxFeePercentage > MathUtils._100_PERCENT)) {
            revert InvalidMaxFeePercentage();
        }
        _;
    }

    modifier onlyActivePosition(IERC20 _collateralToken, address _borrower) {
        if (!sortedPositions[_collateralToken].nodes[_borrower].exists) {
            revert PositionNotActive();
        }
        _;
    }

    // --- Constructor ---

    constructor(uint256 _liquidationProtocolFee, address[] memory delegates) FeeCollector(msg.sender) {
        rToken = new RToken(address(this), msg.sender);
        raftDebtToken = new ERC20Indexable(
            address(this),
            string(bytes.concat("Raft ", bytes(IERC20Metadata(address(rToken)).name()), " debt")),
            string(bytes.concat("r", bytes(IERC20Metadata(address(rToken)).symbol()), "-d"))
        );
        setLiquidationProtocolFee(_liquidationProtocolFee);
        setMinDebt(3000e18);
        for (uint256 i = 0; i < delegates.length; ++i) {
            if (delegates[i] == address(0)) {
                revert InvalidDelegateAddress();
            }
            globalDelegateWhitelist[delegates[i]] = true;
        }

        emit PositionManagerDeployed(rToken, raftDebtToken, msg.sender);
    }

    function addCollateralToken(IERC20 _collateralToken, IPriceFeed _priceFeed, uint256 _positionsSize)
        external
        override
        onlyOwner
    {
        _addCollateralToken(_collateralToken, _priceFeed, _positionsSize);
    }

    function setLiquidationProtocolFee(uint256 _liquidationProtocolFee) public override onlyOwner {
        if (_liquidationProtocolFee > MAX_LIQUIDATION_PROTOCOL_FEE) {
            revert LiquidationProtocolFeeOutOfBound();
        }

        liquidationProtocolFee = _liquidationProtocolFee;
        emit LiquidationProtocolFeeChanged(_liquidationProtocolFee);
    }

    function setMinDebt(uint256 newMinDebt) public override onlyOwner {
        if (newMinDebt == 0) {
            revert MinNetDebtCannotBeZero();
        }
        minDebt = newMinDebt;
        emit MinDebtChanged(newMinDebt);
    }

    function managePosition(
        IERC20 _collateralToken,
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
            _collateralToken,
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
        IERC20 _collateralToken,
        uint256 _collChange,
        bool _isCollIncrease,
        uint256 _rChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external override {
        _managePosition(
            _collateralToken,
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
        IERC20 _collateralToken,
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
        collateralTokenExists(_collateralToken)
        validMaxFeePercentageWhen(_maxFeePercentage, _isDebtIncrease)
        onlyDepositedCollateralTokenOrNew(_borrower, _collateralToken)
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
        _adjustDebt(_borrower, _rChange, _isDebtIncrease, _maxFeePercentage);
        _adjustCollateral(_collateralToken, _borrower, _collChange, _isCollIncrease, _needsCollateralTransfer);

        if (raftDebtToken.balanceOf(_borrower) == 0) {
            // position was closed, remove it
            _removePositionFromSortedPositions(_collateralToken, _borrower);
        } else {
            checkValidPosition(_collateralToken, _borrower);
            bool newPosition = !sortedPositions[_collateralToken].nodes[_borrower].exists;
            sortedPositions[_collateralToken].update(
                this, _collateralToken, _borrower, getNominalICR(_collateralToken, _borrower), _upperHint, _lowerHint
            );
            if (newPosition) {
                collateralTokenPerBorrowers[_borrower] = _collateralToken;
                emit PositionCreated(_borrower);
            }
        }
    }

    function _adjustDebt(address _borrower, uint256 _rChange, bool _isDebtIncrease, uint256 _maxFeePercentage)
        internal
    {
        if (_rChange == 0) {
            return;
        }

        if (_isDebtIncrease) {
            uint256 debtChange = _rChange + _triggerBorrowingFee(_borrower, _rChange, _maxFeePercentage);
            raftDebtToken.mint(_borrower, debtChange);
            totalDebt += debtChange;
            rToken.mint(_borrower, _rChange);
        } else {
            totalDebt -= _rChange;
            raftDebtToken.burn(_borrower, _rChange);
            rToken.burn(_borrower, _rChange);
        }

        emit DebtChanged(_borrower, _rChange, _isDebtIncrease);
    }

    function _adjustCollateral(
        IERC20 _collateralToken,
        address _borrower,
        uint256 _collChange,
        bool _isCollIncrease,
        bool _needsCollTransfer
    ) internal {
        if (_collChange == 0) {
            return;
        }

        if (_isCollIncrease) {
            raftCollateralTokens[_collateralToken].mint(_borrower, _collChange);
            if (_needsCollTransfer) {
                _collateralToken.safeTransferFrom(msg.sender, address(this), _collChange);
            }
        } else {
            raftCollateralTokens[_collateralToken].burn(_borrower, _collChange);
            if (_needsCollTransfer) {
                _collateralToken.safeTransfer(_borrower, _collChange);
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
    function liquidate(IERC20 _collateralToken, address _borrower)
        external
        override
        onlyActivePosition(_collateralToken, _borrower)
    {
        address[] memory borrowers = new address[](1);
        borrowers[0] = _borrower;
        batchLiquidatePositions(_collateralToken, borrowers);
    }

    // --- Inner single liquidation functions ---

    // Liquidate one position
    function _liquidate(
        IERC20 _collateralToken,
        LiquidationTotals memory _oldLiquidationTotals,
        address _borrower,
        uint256 _ICR,
        uint256 _price
    ) internal returns (LiquidationTotals memory newLiquidationTotals) {
        newLiquidationTotals =
            increaseLiquidationTotals(_collateralToken, _oldLiquidationTotals, _borrower, _ICR, _price);

        _removePositionFromSortedPositions(_collateralToken, _borrower);
        raftDebtToken.burn(_borrower, type(uint256).max);
        raftCollateralTokens[_collateralToken].burn(_borrower, type(uint256).max);

        emit PositionLiquidated(_borrower);
    }

    function increaseLiquidationTotals(
        IERC20 collateralToken,
        LiquidationTotals memory oldLiquidationTotals,
        address borrower,
        uint256 icr,
        uint256 price
    ) internal view returns (LiquidationTotals memory) {
        uint256 entirePositionDebt = raftDebtToken.balanceOf(borrower);
        uint256 entirePositionColl = raftCollateralTokens[collateralToken].balanceOf(borrower);
        bool isRedistribution = icr <= MathUtils._100_PERCENT;

        (uint256 collToSendToProtocol, uint256 collToSendToLiquidator) =
            splitLiquidationCollateral(entirePositionColl, entirePositionDebt, price, isRedistribution);
        oldLiquidationTotals.collToSendToProtocol += collToSendToProtocol;
        oldLiquidationTotals.collToSendToLiquidator += collToSendToLiquidator;

        if (isRedistribution) {
            assert(collToSendToProtocol == 0);
            oldLiquidationTotals.debtToRedistribute += entirePositionDebt;
            oldLiquidationTotals.collToRedistribute += entirePositionColl - collToSendToLiquidator;
        } else {
            oldLiquidationTotals.debtToOffset += entirePositionDebt;
        }

        return (oldLiquidationTotals);
    }

    function simulateBatchLiquidatePositions(IERC20 _collateralToken, address[] memory _positionArray, uint256 _price)
        external
        view
        override
        returns (LiquidationTotals memory totals)
    {
        uint256 _positionArrayLength = _positionArray.length;
        for (uint256 i = 0; i < _positionArrayLength; ++i) {
            address user = _positionArray[i];
            IERC20 collateralTokenPerBorrower = collateralTokenPerBorrowers[user];
            if (_collateralToken == collateralTokenPerBorrower) {
                uint256 ICR = getCurrentICR(_collateralToken, user, _price);

                if (ICR < MathUtils.MCR) {
                    // Add liquidation values to their respective running totals
                    totals = increaseLiquidationTotals(_collateralToken, totals, user, ICR, _price);
                }
            }
        }
    }

    /*
    * Attempt to liquidate a custom list of positions provided by the caller.
    */
    function batchLiquidatePositions(IERC20 _collateralToken, address[] memory _positionArray) public override {
        if (_positionArray.length == 0) {
            revert PositionArrayEmpty();
        }

        // Perform the appropriate liquidation sequence - tally values and obtain their totals.
        LiquidationTotals memory totals = _batchLiquidate(_collateralToken, _positionArray);

        if (totals.collToRedistribute + totals.collToSendToLiquidator == 0) {
            revert NothingToLiquidate();
        }

        _collateralToken.transfer(msg.sender, totals.collToSendToLiquidator);
        _collateralToken.transfer(feeRecipient, totals.collToSendToProtocol);

        if (totals.debtToOffset != 0) {
            rToken.burn(msg.sender, totals.debtToOffset);
            totalDebt -= totals.debtToOffset;
        }

        updateDebtAndCollIndex(_collateralToken);

        emit Liquidation(
            msg.sender,
            _collateralToken,
            totals.debtToOffset,
            totals.collToSendToProtocol,
            totals.collToSendToLiquidator,
            totals.debtToRedistribute,
            totals.collToRedistribute
        );
    }

    function _batchLiquidate(IERC20 _collateralToken, address[] memory _positionArray)
        internal
        returns (LiquidationTotals memory totals)
    {
        uint256 price = priceFeeds[_collateralToken].fetchPrice();
        uint256 _positionArrayLength = _positionArray.length;
        for (uint256 i = 0; i < _positionArrayLength; ++i) {
            address user = _positionArray[i];
            IERC20 collateralTokenPerBorrower = collateralTokenPerBorrowers[user];
            if (_collateralToken == collateralTokenPerBorrower) {
                uint256 ICR = getCurrentICR(_collateralToken, user, price);

                if (ICR < MathUtils.MCR) {
                    // Add liquidation values to their respective running totals
                    totals = _liquidate(_collateralToken, totals, user, ICR, price);
                }
            }
        }
    }

    // --- Redemption functions ---

    // Redeem as much collateral as possible from _borrower's Position in exchange for R up to _maxRAmount
    function _redeemCollateralFromPosition(
        IERC20 _collateralToken,
        address _borrower,
        uint256 _maxRAmount,
        uint256 _price,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint256 _partialRedemptionHintNICR
    ) internal returns (uint256 rLot) {
        uint256 positionDebt = raftDebtToken.balanceOf(_borrower);
        // Determine the remaining amount (lot) to be redeemed, capped by the entire debt of the Position
        rLot = Math.min(_maxRAmount, positionDebt);
        uint256 collateralToRedeem = rLot.divDown(_price);

        // Decrease the debt and collateral of the current Position according to the R lot and corresponding
        // collateralToken to send
        uint256 newDebt = positionDebt - rLot;
        uint256 newColl = raftCollateralTokens[_collateralToken].balanceOf(_borrower) - collateralToRedeem;

        if (newDebt == 0) {
            // No debt left in the Position (except for the liquidation reserve), therefore the position gets closed
            _removePositionFromSortedPositions(_collateralToken, _borrower);
            raftDebtToken.burn(_borrower, type(uint256).max);
            raftCollateralTokens[_collateralToken].burn(_borrower, type(uint256).max);
            _collateralToken.safeTransfer(_borrower, newColl);
        } else {
            uint256 newNICR = MathUtils.computeNominalCR(newColl, newDebt);

            /*
            * If the provided hint is out of date, we bail since trying to reinsert without a good hint will almost
            * certainly result in running out of gas.
            *
            * If the resultant net debt of the partial is less than the minimum, net debt we bail.
            */
            if (newNICR != _partialRedemptionHintNICR || newDebt < minDebt) {
                rLot = 0;
            } else {
                sortedPositions[_collateralToken].update(
                    this, _collateralToken, _borrower, newNICR, _upperPartialRedemptionHint, _lowerPartialRedemptionHint
                );

                raftDebtToken.burn(_borrower, rLot);
                raftCollateralTokens[_collateralToken].burn(_borrower, collateralToRedeem);
            }
        }
    }

    function _isValidFirstRedemptionHint(IERC20 _collateralToken, address _firstRedemptionHint, uint256 _price)
        internal
        view
        returns (bool)
    {
        if (
            _firstRedemptionHint == address(0) || !sortedPositions[_collateralToken].nodes[_firstRedemptionHint].exists
                || getCurrentICR(_collateralToken, _firstRedemptionHint, _price) < MathUtils.MCR
        ) {
            return false;
        }

        address nextPosition = sortedPositions[_collateralToken].nodes[_firstRedemptionHint].nextId;
        return nextPosition == address(0) || getCurrentICR(_collateralToken, nextPosition, _price) < MathUtils.MCR;
    }

    /* Send _rAmount R to the system and redeem the corresponding amount of collateral from as many Positions as are
    needed to fill the redemption
    * request.  Applies pending rewards to a Position before reducing its debt and coll.
    *
    * Note that if _amount is very large, this function can run out of gas, specially if traversed positions are small.
    This can be easily avoided by
    * splitting the total _amount in appropriate chunks and calling the function multiple times.
    *
    * Param `_maxIterations` can also be provided, so the loop through Positions is capped (if it’s zero, it will be
    ignored).This makes it easier to
    * avoid OOG for the frontend, as only knowing approximately the average cost of an iteration is enough, without
    needing to know the “topology”
    * of the position list. It also avoids the need to set the cap in stone in the contract, nor doing gas calculations,
    as both gas price and opcode
    * costs can vary.
    *
    * All Positions that are redeemed from -- with the likely exception of the last one -- will end up with no debt
    left, therefore they will be closed.
    * If the last Position does have some remaining debt, it has a finite ICR, and the reinsertion could be anywhere in
    the list, therefore it requires a hint.
    * A frontend should use getRedemptionHints() to calculate what the ICR of this Position will be after redemption,
    and pass a hint for its position
    * in the sortedPositions list along with the ICR value that the hint was found for.
    *
    * If another transaction modifies the list between calling getRedemptionHints() and passing the hints to
    redeemCollateral(), it
    * is very likely that the last (partially) redeemed Position would end up with a different ICR than what the hint is
    for. In this case the
    * redemption will stop after the last completely redeemed Position and the sender will keep the remaining R amount,
    which they can attempt
    * to redeem later.
    */
    // solhint-disable-next-line code-complexity
    function redeemCollateral(
        IERC20 _collateralToken,
        uint256 _rAmount,
        address _firstRedemptionHint,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint256 _partialRedemptionHintNICR,
        uint256 _maxIterations,
        uint256 _maxFeePercentage
    ) external override {
        if (_maxFeePercentage < REDEMPTION_FEE_FLOOR || _maxFeePercentage > MathUtils._100_PERCENT) {
            revert MaxFeePercentageOutOfRange();
        }
        if (_rAmount == 0) {
            revert AmountIsZero();
        }
        if (rToken.balanceOf(msg.sender) < _rAmount) {
            revert RedemptionAmountExceedsBalance();
        }

        address currentBorrower;

        uint256 price = priceFeeds[_collateralToken].fetchPrice();
        if (_isValidFirstRedemptionHint(_collateralToken, _firstRedemptionHint, price)) {
            currentBorrower = _firstRedemptionHint;
        } else {
            currentBorrower = sortedPositions[_collateralToken].last;
            // Find the first position with ICR >= MathUtils.MCR
            while (
                currentBorrower != address(0) && getCurrentICR(_collateralToken, currentBorrower, price) < MathUtils.MCR
            ) {
                currentBorrower = sortedPositions[_collateralToken].nodes[currentBorrower].prevId;
            }
        }

        uint256 remainingR = _rAmount;
        // Loop through the Positions starting from the one with lowest collateral ratio until _amount of R is exchanged
        // for collateral
        if (_maxIterations == 0) _maxIterations = type(uint256).max;
        while (currentBorrower != address(0) && remainingR > 0 && _maxIterations > 0) {
            _maxIterations--;
            // Save the address of the Position preceding the current one, before potentially modifying the list
            address nextUserToCheck = sortedPositions[_collateralToken].nodes[currentBorrower].prevId;

            uint256 rLot = _redeemCollateralFromPosition(
                _collateralToken,
                currentBorrower,
                remainingR,
                price,
                _upperPartialRedemptionHint,
                _lowerPartialRedemptionHint,
                _partialRedemptionHintNICR
            );

            if (rLot == 0) break; // Partial redemption was cancelled (out-of-date hint, or new net debt < minimum),
                // therefore we could not redeem from the last Position

            remainingR -= rLot;
            currentBorrower = nextUserToCheck;
        }
        uint256 totalRRedeemed = _rAmount - remainingR;
        uint256 totalCollateralTokenDrawn = totalRRedeemed.divDown(price);

        if (totalCollateralTokenDrawn == 0) {
            revert UnableToRedeemAnyAmount();
        }

        // Decay the baseRate due to time passed, and then increase it according to the size of this redemption.
        // Use the saved total R supply value, from before it was reduced by the redemption.
        _updateBaseRateFromRedemption(totalCollateralTokenDrawn, price, rToken.totalSupply());

        // Calculate the collateralToken fee
        uint256 collateralTokenFee = _calcRedemptionFee(getRedemptionRate(), totalCollateralTokenDrawn);

        checkValidFee(collateralTokenFee, totalCollateralTokenDrawn, _maxFeePercentage);

        // Send the collateralToken fee to the recipient
        _collateralToken.safeTransfer(feeRecipient, collateralTokenFee);

        emit Redemption(_rAmount, totalRRedeemed, totalCollateralTokenDrawn, collateralTokenFee);

        // Burn the total R that is cancelled with debt, and send the redeemed collateralToken to msg.sender
        rToken.burn(msg.sender, totalRRedeemed);
        totalDebt -= totalRRedeemed;

        // Send collateralToken to account
        uint256 collateralTokenToSendToRedeemer = totalCollateralTokenDrawn - collateralTokenFee;
        _collateralToken.safeTransfer(msg.sender, collateralTokenToSendToRedeemer);
    }

    // --- Helper functions ---

    // Return the nominal collateral ratio (ICR) of a given Position, without the price. Takes a position's pending coll
    // and debt rewards from redistributions into account.
    function getNominalICR(IERC20 collateralToken, address borrower) public view override returns (uint256 nicr) {
        return MathUtils.computeNominalCR(
            raftCollateralTokens[collateralToken].balanceOf(borrower), raftDebtToken.balanceOf(borrower)
        );
    }

    // Return the current collateral ratio (ICR) of a given Position. Takes a position's pending coll and debt rewards
    // from redistributions into account.
    function getCurrentICR(IERC20 collateralToken, address borrower, uint256 price)
        public
        view
        override
        returns (uint256)
    {
        return MathUtils.computeCR(
            raftCollateralTokens[collateralToken].balanceOf(borrower), raftDebtToken.balanceOf(borrower), price
        );
    }

    function updateDebtAndCollIndex(IERC20 _collateralToken) internal {
        raftDebtToken.setIndex(totalDebt);
        raftCollateralTokens[_collateralToken].setIndex(_collateralToken.balanceOf(address(this)));
    }

    function _removePositionFromSortedPositions(IERC20 _collateralToken, address _borrower) internal {
        if (sortedPositions[_collateralToken].size <= 1) {
            revert OnlyOnePositionInSystem();
        }
        sortedPositions[_collateralToken].remove(_borrower);
        collateralTokenPerBorrowers[_borrower] = IERC20(address(0));
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
        newBaseRate = Math.min(newBaseRate, MathUtils._100_PERCENT); // cap baseRate at a maximum of 100%
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
        return Math.min(REDEMPTION_FEE_FLOOR + _baseRate, MathUtils._100_PERCENT);
    }

    function getRedemptionFeeWithDecay(uint256 _collateralDrawn) external view override returns (uint256) {
        return _calcRedemptionFee(getRedemptionRateWithDecay(), _collateralDrawn);
    }

    function _calcRedemptionFee(uint256 _redemptionRate, uint256 _collateralDrawn)
        internal
        pure
        returns (uint256 redemptionFee)
    {
        redemptionFee = _redemptionRate.mulDown(_collateralDrawn);
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
        return _borrowingRate.mulDown(_rDebt);
    }

    // Updates the baseRate state variable based on time elapsed since the last redemption or R borrowing operation.
    function _decayBaseRateFromBorrowing() internal {
        uint256 decayedBaseRate = _calcDecayedBaseRate();
        assert(decayedBaseRate <= MathUtils._100_PERCENT); // The baseRate can decay to 0

        baseRate = decayedBaseRate;
        emit BaseRateUpdated(decayedBaseRate);

        _updateLastFeeOpTime();
    }

    // --- Internal fee functions ---

    // Add a new collateral token to the system
    function _addCollateralToken(IERC20 _collateralToken, IPriceFeed _priceFeed, uint256 _positionsSize) internal {
        if (address(raftCollateralTokens[_collateralToken]) != address(0)) {
            revert CollateralTokenAlreadyAdded();
        }
        raftCollateralTokens[_collateralToken] = new ERC20Indexable(
            address(this),
            string(bytes.concat("Raft ", bytes(IERC20Metadata(address(_collateralToken)).name()), " collateral")),
            string(bytes.concat("r", bytes(IERC20Metadata(address(_collateralToken)).symbol()), "-c"))
        );
        priceFeeds[_collateralToken] = _priceFeed;
        sortedPositions[_collateralToken].maxSize = _positionsSize;
        emit CollateralTokenAdded(_collateralToken, raftCollateralTokens[_collateralToken], _priceFeed, _positionsSize);
    }

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

        return baseRate.mulDown(decayFactor);
    }

    /// ---- Liquidation fee functions ---

    function splitLiquidationCollateral(uint256 collateral, uint256 debt, uint256 price, bool isRedistribution)
        internal
        view
        returns (uint256 collToSendToProtocol, uint256 collToSentToLiquidator)
    {
        if (isRedistribution) {
            collToSendToProtocol = 0;
            collToSentToLiquidator = collateral / 200;
        } else {
            uint256 debtValue = debt.divDown(price);
            uint256 excessCollateral = collateral - debtValue;
            collToSendToProtocol = excessCollateral.mulDown(liquidationProtocolFee);
            collToSentToLiquidator = collateral - collToSendToProtocol;
        }
    }

    // --- Helper functions ---

    function _triggerBorrowingFee(address _borrower, uint256 _rAmount, uint256 _maxFeePercentage)
        internal
        returns (uint256 rFee)
    {
        _decayBaseRateFromBorrowing(); // decay the baseRate state variable
        rFee = _getBorrowingFee(_rAmount);

        checkValidFee(rFee, _rAmount, _maxFeePercentage);

        if (rFee > 0) {
            rToken.mint(feeRecipient, rFee);
            emit RBorrowingFeePaid(_borrower, rFee);
        }
    }

    function checkValidPosition(IERC20 _collateralToken, address position) internal {
        uint256 positionDebt = raftDebtToken.balanceOf(position);
        if (positionDebt < minDebt) {
            revert NetDebtBelowMinimum(positionDebt);
        }

        uint256 newICR = getCurrentICR(_collateralToken, position, priceFeeds[_collateralToken].fetchPrice());
        if (newICR < MathUtils.MCR) {
            revert NewICRLowerThanMCR(newICR);
        }
    }

    function checkValidFee(uint256 _fee, uint256 _amount, uint256 _maxFeePercentage) internal pure {
        uint256 feePercentage = _fee.divDown(_amount);

        if (feePercentage > _maxFeePercentage) {
            revert FeeExceedsMaxFee(_fee, _amount, _maxFeePercentage);
        }
    }

    function sortedPositionsNodes(IERC20 _collateralToken, address _id)
        external
        view
        override
        returns (bool exists, address nextId, address prevId)
    {
        exists = sortedPositions[_collateralToken].nodes[_id].exists;
        nextId = sortedPositions[_collateralToken].nodes[_id].nextId;
        prevId = sortedPositions[_collateralToken].nodes[_id].prevId;
    }
}
