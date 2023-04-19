// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Fixed256x18} from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import {MathUtils} from "./Dependencies/MathUtils.sol";
import {IERC20Indexable} from "./Interfaces/IERC20Indexable.sol";
import {IPositionManager} from "./Interfaces/IPositionManager.sol";
import {IPriceFeed} from "./Interfaces/IPriceFeed.sol";
import {ISplitLiquidationCollateral} from "./Interfaces/ISplitLiquidationCollateral.sol";
import {ERC20Indexable} from "./ERC20Indexable.sol";
import {FeeCollector} from "./FeeCollector.sol";
import {RToken, IRToken} from "./RToken.sol";
import {SortedPositions} from "./SortedPositions.sol";

contract PositionManager is FeeCollector, IPositionManager {
    using SafeERC20 for IERC20;
    using SortedPositions for SortedPositions.Data;
    using Fixed256x18 for uint256;

    IRToken public immutable override rToken;

    IERC20Indexable public immutable override raftDebtToken;

    mapping(IERC20 collateralToken => IERC20Indexable raftCollateralToken) public override raftCollateralTokens;

    mapping(IERC20 collateralToken => IPriceFeed priceFeed) public override priceFeeds;

    mapping(address borrower => IERC20 collateralToken) public override collateralTokenForBorrower;

    mapping(address delegate => bool isWhitelisted) public override globalDelegateWhitelist;
    mapping(address borrower => mapping(address delegate => bool isWhitelisted)) public override
        individualDelegateWhitelist;

    uint256 public override liquidationProtocolFee;
    uint256 public override minDebt;

    ISplitLiquidationCollateral public override splitLiquidationCollateral;

    mapping(IERC20 collateralToken => SortedPositions.Data data) public override sortedPositions;

    /// @notice Half-life of 12h (720 min).
    /// @dev (1/2) = d^720 => d = (1/2)^(1/720)
    uint256 public constant MINUTE_DECAY_FACTOR = 999_037_758_833_783_000;

    uint256 public constant MIN_REDEMPTION_SPREAD = MathUtils._100_PERCENT / 10000 * 25; // 0.25%
    uint256 public constant MAX_REDEMPTION_SPREAD = MathUtils._100_PERCENT / 100 * 2; // 2%
    uint256 public constant override MAX_BORROWING_SPREAD = MathUtils._100_PERCENT / 100; // 1%
    uint256 public constant MAX_BORROWING_FEE = MathUtils._100_PERCENT / 100 * 5; // 5%
    uint256 public constant override MAX_LIQUIDATION_PROTOCOL_FEE = MathUtils._100_PERCENT / 100 * 80; // 80%

    /// @dev Parameter by which to divide the redeemed fraction, in order to calc the new base rate from a redemption.
    /// Corresponds to (1 / ALPHA) in the white paper.
    uint256 public constant BETA = 2;

    uint256 public override borrowingSpread;
    uint256 public override redemptionSpread;
    uint256 public baseRate;

    /// @dev The timestamp of the latest fee operation (redemption or new R issuance).
    uint256 public lastFeeOperationTime;

    uint256 private totalDebt;

    /// @dev Checks if the collateral token has been added to the position manager, or reverts otherwise.
    /// @param _collateralToken The collateral token to check.
    modifier collateralTokenExists(IERC20 _collateralToken) {
        if (address(raftCollateralTokens[_collateralToken]) == address(0)) {
            revert CollateralTokenNotAdded();
        }
        _;
    }

    /// @dev Checks if the borrower has a position with the collateral token or doesn't have a position at all, or
    /// reverts otherwise.
    /// @param _borrower The borrower to check.
    /// @param _collateralToken The collateral token to check.
    modifier onlyDepositedCollateralTokenOrNew(address _borrower, IERC20 _collateralToken) {
        if (
            collateralTokenForBorrower[_borrower] != IERC20(address(0))
                && collateralTokenForBorrower[_borrower] != _collateralToken
        ) {
            revert BorrowerHasDifferentCollateralToken();
        }
        _;
    }

    /// @dev Checks if the max fee percentage is between the borrowing spread and 100%, or reverts otherwise. When the
    /// condition is false, the check is skipped.
    /// @param _maxFeePercentage The max fee percentage to check.
    /// @param condition If true, the check will be performed.
    modifier validMaxFeePercentageWhen(uint256 _maxFeePercentage, bool condition) {
        if (condition && (_maxFeePercentage < borrowingSpread || _maxFeePercentage > MathUtils._100_PERCENT)) {
            revert InvalidMaxFeePercentage();
        }
        _;
    }

    /// @dev Checks if the borrower has an active position with the collateral token, or reverts otherwise.
    /// @param _collateralToken The collateral token to check.
    /// @param _borrower The borrower to check.
    modifier onlyActivePosition(IERC20 _collateralToken, address _borrower) {
        if (!sortedPositions[_collateralToken].nodes[_borrower].exists) {
            revert PositionNotActive();
        }
        _;
    }

    // --- Constructor ---

    /// @dev Initializes the position manager.
    /// @param _liquidationProtocolFee The liquidation protocol fee.
    /// @param delegates The delegates to whitelist.
    /// @param newSplitLiquidationCollateral The split liquidation collateral contract.
    constructor(
        uint256 _liquidationProtocolFee,
        address[] memory delegates,
        ISplitLiquidationCollateral newSplitLiquidationCollateral
    ) FeeCollector(msg.sender) {
        rToken = new RToken(address(this), msg.sender);
        raftDebtToken = new ERC20Indexable(
            address(this),
            string(bytes.concat("Raft ", bytes(IERC20Metadata(address(rToken)).name()), " debt")),
            string(bytes.concat("r", bytes(IERC20Metadata(address(rToken)).symbol()), "-d"))
        );
        setLiquidationProtocolFee(_liquidationProtocolFee);
        setRedemptionSpread(MathUtils._100_PERCENT / 100);
        setMinDebt(3000e18);
        setSplitLiquidationCollateral(newSplitLiquidationCollateral);
        for (uint256 i = 0; i < delegates.length; ++i) {
            setGlobalDelegateWhitelist(delegates[i], true);
        }

        emit PositionManagerDeployed(rToken, raftDebtToken, msg.sender);
    }

    function setGlobalDelegateWhitelist(address delegate, bool isWhitelisted) public override onlyOwner {
        if (delegate == address(0)) {
            revert InvalidDelegateAddress();
        }
        globalDelegateWhitelist[delegate] = isWhitelisted;

        emit GlobalDelegateUpdated(delegate, isWhitelisted);
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

    function setSplitLiquidationCollateral(ISplitLiquidationCollateral newSplitLiquidationCollateral)
        public
        override
        onlyOwner
    {
        if (address(newSplitLiquidationCollateral) == address(0)) {
            revert SplitLiquidationCollateralCannotBeZero();
        }
        splitLiquidationCollateral = newSplitLiquidationCollateral;
        emit SplitLiquidationCollateralChanged(newSplitLiquidationCollateral);
    }

    function managePosition(
        IERC20 _collateralToken,
        address _borrower,
        uint256 _collateralChange,
        bool _isCollateralIncrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external override {
        _managePosition(
            _collateralToken,
            _borrower,
            _collateralChange,
            _isCollateralIncrease,
            _debtChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _maxFeePercentage,
            true
        );
    }

    function managePosition(
        IERC20 _collateralToken,
        uint256 _collateralChange,
        bool _isCollateralIncrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _maxFeePercentage
    ) external override {
        _managePosition(
            _collateralToken,
            msg.sender,
            _collateralChange,
            _isCollateralIncrease,
            _debtChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _maxFeePercentage,
            true
        );
    }

    /// @dev Manages the position on behalf of a given borrower.
    /// @param _collateralToken The token the borrower used as collateral.
    /// @param _borrower The address of the borrower.
    /// @param _collateralChange The amount of collateral to add or remove.
    /// @param _isCollateralIncrease True if the collateral is being increased, false otherwise.
    /// @param _debtChange The amount of R to add or remove.
    /// @param _isDebtIncrease True if the debt is being increased, false otherwise.
    /// @param _upperHint The upper hint for the position ID.
    /// @param _lowerHint The lower hint for the position ID.
    /// @param _maxFeePercentage The maximum fee percentage to pay for the position management.
    function _managePosition(
        IERC20 _collateralToken,
        address _borrower,
        uint256 _collateralChange,
        bool _isCollateralIncrease,
        uint256 _debtChange,
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
        if (_collateralChange == 0 && _debtChange == 0) {
            revert NoCollateralOrDebtChange();
        }
        _adjustDebt(_borrower, _debtChange, _isDebtIncrease, _maxFeePercentage);
        _adjustCollateral(
            _collateralToken, _borrower, _collateralChange, _isCollateralIncrease, _needsCollateralTransfer
        );

        if (raftDebtToken.balanceOf(_borrower) == 0) {
            // position was closed, remove it
            _removePositionFromSortedPositions(_collateralToken, _borrower, false);
        } else {
            checkValidPosition(_collateralToken, _borrower);
            bool newPosition = !sortedPositions[_collateralToken].nodes[_borrower].exists;
            sortedPositions[_collateralToken]._update(
                this, _collateralToken, _borrower, getNominalICR(_collateralToken, _borrower), _upperHint, _lowerHint
            );
            if (newPosition) {
                collateralTokenForBorrower[_borrower] = _collateralToken;
                emit PositionCreated(_borrower);
            }
        }
    }

    /// @dev Adjusts the debt of a given borrower by burning or minting the corresponding amount of R and the Raft
    /// debt token. If the debt is being increased, the borrowing fee is also triggered.
    /// @param _borrower The address of the borrower.
    /// @param _debtChange The amount of R to add or remove. Must be positive.
    /// @param _isDebtIncrease True if the debt is being increased, false otherwise.
    /// @param _maxFeePercentage The maximum fee percentage.
    function _adjustDebt(address _borrower, uint256 _debtChange, bool _isDebtIncrease, uint256 _maxFeePercentage)
        internal
    {
        if (_debtChange == 0) {
            return;
        }

        if (_isDebtIncrease) {
            uint256 debtChange = _debtChange + _triggerBorrowingFee(_borrower, _debtChange, _maxFeePercentage);
            raftDebtToken.mint(_borrower, debtChange);
            totalDebt += debtChange;
            rToken.mint(_borrower, _debtChange);
        } else {
            totalDebt -= _debtChange;
            raftDebtToken.burn(_borrower, _debtChange);
            rToken.burn(_borrower, _debtChange);
        }

        emit DebtChanged(_borrower, _debtChange, _isDebtIncrease);
    }

    /// @dev Adjusts the collateral of a given borrower by burning or minting the corresponding amount of Raft
    /// collateral token and transferring the corresponding amount of collateral token.
    /// @param _collateralToken The token the borrower used as collateral.
    /// @param _borrower The address of the borrower.
    /// @param _collateralChange The amount of collateral to add or remove. Must be positive.
    /// @param _isCollateralIncrease True if the collateral is being increased, false otherwise.
    /// @param _needsCollateralTransfer True if the collateral token needs to be transferred, false otherwise.
    function _adjustCollateral(
        IERC20 _collateralToken,
        address _borrower,
        uint256 _collateralChange,
        bool _isCollateralIncrease,
        bool _needsCollateralTransfer
    ) internal {
        if (_collateralChange == 0) {
            return;
        }

        if (_isCollateralIncrease) {
            raftCollateralTokens[_collateralToken].mint(_borrower, _collateralChange);
            if (_needsCollateralTransfer) {
                _collateralToken.safeTransferFrom(msg.sender, address(this), _collateralChange);
            }
        } else {
            raftCollateralTokens[_collateralToken].burn(_borrower, _collateralChange);
            if (_needsCollateralTransfer) {
                _collateralToken.safeTransfer(_borrower, _collateralChange);
            }
        }

        emit CollateralChanged(_borrower, _collateralChange, _isCollateralIncrease);
    }

    function whitelistDelegate(address delegate) external override {
        if (delegate == address(0)) {
            revert InvalidDelegateAddress();
        }
        individualDelegateWhitelist[msg.sender][delegate] = true;
    }

    // --- Position Liquidation functions ---

    function liquidate(IERC20 collateralToken, address borrower)
        external
        override
        onlyActivePosition(collateralToken, borrower)
    {
        uint256 price = priceFeeds[collateralToken].fetchPrice();
        uint256 icr = getCurrentICR(collateralToken, borrower, price);
        if (icr >= MathUtils.MCR) {
            revert NothingToLiquidate();
        }

        uint256 entirePositionDebt = raftDebtToken.balanceOf(borrower);
        uint256 entirePositionCollateral = raftCollateralTokens[collateralToken].balanceOf(borrower);
        bool isRedistribution = icr <= MathUtils._100_PERCENT;

        (uint256 collateralLiquidationFee, uint256 collateralToSendToLiquidator) = splitLiquidationCollateral.split(
            entirePositionCollateral, entirePositionDebt, price, isRedistribution, liquidationProtocolFee
        );

        if (!isRedistribution) {
            rToken.burn(msg.sender, entirePositionDebt);
            totalDebt -= entirePositionDebt;
            // Collateral is sent to protocol as a fee only in case of liquidation
            collateralToken.transfer(feeRecipient, collateralLiquidationFee);
        }

        collateralToken.transfer(msg.sender, collateralToSendToLiquidator);

        _removePositionFromSortedPositions(collateralToken, borrower, true);

        updateDebtAndCollateralIndex(collateralToken);

        emit Liquidation(
            msg.sender,
            borrower,
            collateralToken,
            entirePositionDebt,
            entirePositionCollateral,
            collateralToSendToLiquidator,
            collateralLiquidationFee,
            isRedistribution
        );
    }

    // --- Redemption functions ---

    /// @dev Redeem as much collateral as possible from the borrower's position in the exchange for R (up to max debt
    /// amount).
    /// @param _collateralToken The token the borrower used as collateral.
    /// @param _borrower The address of the borrower.
    /// @param maxDebtAmount The maximum amount of R to redeem.
    /// @param _price The price of the collateral token.
    /// @param _upperPartialRedemptionHint The address of the upper partial redemption hint.
    /// @param _lowerPartialRedemptionHint The address of the lower partial redemption hint.
    /// @param _partialRedemptionHintNICR The NICR of the partial redemption hint.
    /// @return debtLot The amount of R redeemed.
    function _redeemCollateralFromPosition(
        IERC20 _collateralToken,
        address _borrower,
        uint256 maxDebtAmount,
        uint256 _price,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint256 _partialRedemptionHintNICR
    ) internal returns (uint256 debtLot) {
        uint256 positionDebt = raftDebtToken.balanceOf(_borrower);
        // Determine the remaining amount (lot) to be redeemed, capped by the entire debt of the Position
        debtLot = Math.min(maxDebtAmount, positionDebt);
        uint256 collateralToRedeem = debtLot.divDown(_price);

        // Decrease the debt and collateral of the current Position according to the R lot and corresponding
        // collateralToken to send
        uint256 newDebt = positionDebt - debtLot;
        uint256 newCollateral = raftCollateralTokens[_collateralToken].balanceOf(_borrower) - collateralToRedeem;

        if (newDebt == 0) {
            // No debt left in the Position (except for the liquidation reserve), therefore the position gets closed
            _removePositionFromSortedPositions(_collateralToken, _borrower, true);
            _collateralToken.safeTransfer(_borrower, newCollateral);
        } else {
            uint256 newNICR = MathUtils._computeNominalCR(newCollateral, newDebt);

            /*
            * If the provided hint is out of date, we bail since trying to reinsert without a good hint will almost
            * certainly result in running out of gas.
            *
            * If the resultant net debt of the partial is less than the minimum, net debt we bail.
            */
            if (newNICR != _partialRedemptionHintNICR || newDebt < minDebt) {
                debtLot = 0;
            } else {
                sortedPositions[_collateralToken]._update(
                    this,
                    _collateralToken,
                    _borrower,
                    newNICR,
                    _upperPartialRedemptionHint,
                    _lowerPartialRedemptionHint
                );

                raftDebtToken.burn(_borrower, debtLot);
                raftCollateralTokens[_collateralToken].burn(_borrower, collateralToRedeem);
            }
        }
    }

    /// @dev Checks if the first redemption hint is valid.
    /// @param _collateralToken The token the borrower used as collateral.
    /// @param _firstRedemptionHint The address of the first redemption hint.
    /// @param _price The price of the collateral token.
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

        address nextPosition = sortedPositions[_collateralToken].nodes[_firstRedemptionHint].nextID;
        return nextPosition == address(0) || getCurrentICR(_collateralToken, nextPosition, _price) < MathUtils.MCR;
    }

    // solhint-disable-next-line code-complexity
    function redeemCollateral(
        IERC20 _collateralToken,
        uint256 debtAmount,
        address _firstRedemptionHint,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint256 _partialRedemptionHintNICR,
        uint256 _maxIterations,
        uint256 _maxFeePercentage
    ) external override {
        if (_maxFeePercentage < MIN_REDEMPTION_SPREAD || _maxFeePercentage > MathUtils._100_PERCENT) {
            revert MaxFeePercentageOutOfRange();
        }
        if (debtAmount == 0) {
            revert AmountIsZero();
        }
        if (rToken.balanceOf(msg.sender) < debtAmount) {
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
                currentBorrower != address(0)
                    && getCurrentICR(_collateralToken, currentBorrower, price) < MathUtils.MCR
            ) {
                currentBorrower = sortedPositions[_collateralToken].nodes[currentBorrower].previousID;
            }
        }

        uint256 remainingDebt = debtAmount;
        // Loop through the Positions starting from the one with lowest collateral ratio until _amount of R is exchanged
        // for collateral
        if (_maxIterations == 0) _maxIterations = type(uint256).max;
        while (currentBorrower != address(0) && remainingDebt > 0 && _maxIterations > 0) {
            _maxIterations--;
            // Save the address of the Position preceding the current one, before potentially modifying the list
            address nextUserToCheck = sortedPositions[_collateralToken].nodes[currentBorrower].previousID;

            uint256 debtLot = _redeemCollateralFromPosition(
                _collateralToken,
                currentBorrower,
                remainingDebt,
                price,
                _upperPartialRedemptionHint,
                _lowerPartialRedemptionHint,
                _partialRedemptionHintNICR
            );

            if (debtLot == 0) break; // Partial redemption was cancelled (out-of-date hint, or new net debt < minimum),
                // therefore we could not redeem from the last Position

            remainingDebt -= debtLot;
            currentBorrower = nextUserToCheck;
        }
        uint256 totalRedeemed = debtAmount - remainingDebt;
        uint256 totalCollateralDrawn = totalRedeemed.divDown(price);

        if (totalCollateralDrawn == 0) {
            revert UnableToRedeemAnyAmount();
        }

        // Decay the baseRate due to time passed, and then increase it according to the size of this redemption.
        // Use the saved total R supply value, from before it was reduced by the redemption.
        _updateBaseRateFromRedemption(totalCollateralDrawn, price, rToken.totalSupply());

        // Calculate the redemption fee
        uint256 redemptionFee = _calcRedemptionFee(getRedemptionRate(), totalCollateralDrawn);

        checkValidFee(redemptionFee, totalCollateralDrawn, _maxFeePercentage);

        // Send the redemption fee to the recipient
        _collateralToken.safeTransfer(feeRecipient, redemptionFee);

        emit Redemption(debtAmount, totalRedeemed, totalCollateralDrawn, redemptionFee);

        // Burn the total R that is cancelled with debt, and send the redeemed collateral to msg.sender
        rToken.burn(msg.sender, totalRedeemed);
        totalDebt -= totalRedeemed;

        // Send collateral to account
        uint256 collateralAmountForRedeemer = totalCollateralDrawn - redemptionFee;
        _collateralToken.safeTransfer(msg.sender, collateralAmountForRedeemer);
    }

    // --- Helper functions ---

    /// @dev Returns the nominal collateral ratio (ICR) of a given position, without the price. Takes the position's
    /// pending collateral and debt rewards from redistributions into account.
    function getNominalICR(IERC20 collateralToken, address borrower) public view override returns (uint256 nicr) {
        return MathUtils._computeNominalCR(
            raftCollateralTokens[collateralToken].balanceOf(borrower), raftDebtToken.balanceOf(borrower)
        );
    }

    /// @dev Returns the current collateral ratio (ICR) of a given position. Takes the position's pending collateral and
    /// debt rewards from redistributions into account.
    function getCurrentICR(IERC20 collateralToken, address borrower, uint256 price)
        public
        view
        override
        returns (uint256)
    {
        return MathUtils._computeCR(
            raftCollateralTokens[collateralToken].balanceOf(borrower), raftDebtToken.balanceOf(borrower), price
        );
    }

    /// @dev Updates debt and collateral indexes for a given collateral token.
    /// @param _collateralToken The collateral token for which to update the indexes.
    function updateDebtAndCollateralIndex(IERC20 _collateralToken) internal {
        raftDebtToken.setIndex(totalDebt);
        raftCollateralTokens[_collateralToken].setIndex(_collateralToken.balanceOf(address(this)));
    }

    function _removePositionFromSortedPositions(IERC20 _collateralToken, address _borrower, bool burnTokens)
        internal
    {
        if (sortedPositions[_collateralToken].size <= 1) {
            revert OnlyOnePositionInSystem();
        }
        sortedPositions[_collateralToken]._remove(_borrower);
        collateralTokenForBorrower[_borrower] = IERC20(address(0));

        if (burnTokens) {
            raftDebtToken.burn(_borrower, type(uint256).max);
            raftCollateralTokens[_collateralToken].burn(_borrower, type(uint256).max);
        }
        emit PositionClosed(_borrower);
    }

    // --- Redemption fee functions ---

    /// @dev Updates the base rate from a redemption operation. Impacts on the base rate:
    /// 1. decays the base rate based on time passed since last redemption or R borrowing operation,
    /// 2. increases the base rate based on the amount redeemed, as a proportion of total supply.
    function _updateBaseRateFromRedemption(uint256 _collateralDrawn, uint256 _price, uint256 _totalRSupply)
        internal
        returns (uint256)
    {
        uint256 decayedBaseRate = _calcDecayedBaseRate();

        /* Convert the drawn collateral back to R at face value rate (1 R:1 USD), in order to get
        * the fraction of total supply that was redeemed at face value. */
        uint256 redeemedFraction = _collateralDrawn * _price / _totalRSupply;

        uint256 newBaseRate = decayedBaseRate + redeemedFraction / BETA;
        newBaseRate = Math.min(newBaseRate, MathUtils._100_PERCENT); // cap baseRate at a maximum of 100%
        assert(newBaseRate > 0); // Base rate is always non-zero after redemption

        // Update the baseRate state variable
        baseRate = newBaseRate;
        emit BaseRateUpdated(newBaseRate);

        _updateLastFeeOpTime();

        return newBaseRate;
    }

    function setRedemptionSpread(uint256 redemptionSpread_) public override onlyOwner {
        if (redemptionSpread_ < MIN_REDEMPTION_SPREAD || redemptionSpread_ > MAX_REDEMPTION_SPREAD) {
            revert RedemptionSpreadOutOfRange();
        }
        redemptionSpread = redemptionSpread_;
        emit RedemptionSpreadUpdated(redemptionSpread_);
    }

    function getRedemptionRate() public view override returns (uint256) {
        return _calcRedemptionRate(baseRate);
    }

    function getRedemptionRateWithDecay() public view override returns (uint256) {
        return _calcRedemptionRate(_calcDecayedBaseRate());
    }

    function _calcRedemptionRate(uint256 _baseRate) internal view returns (uint256) {
        return _baseRate + redemptionSpread;
    }

    function getRedemptionFeeWithDecay(uint256 _collateralAmount) external view override returns (uint256) {
        return _calcRedemptionFee(getRedemptionRateWithDecay(), _collateralAmount);
    }

    function _calcRedemptionFee(uint256 _redemptionRate, uint256 _collateralAmount)
        internal
        pure
        returns (uint256 redemptionFee)
    {
        redemptionFee = _redemptionRate.mulDown(_collateralAmount);
        if (redemptionFee >= _collateralAmount) {
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

    /// @dev Updates the base rate based on time elapsed since the last redemption or R borrowing operation.
    function _decayBaseRateFromBorrowing() internal {
        uint256 decayedBaseRate = _calcDecayedBaseRate();
        assert(decayedBaseRate <= MathUtils._100_PERCENT); // The baseRate can decay to 0

        baseRate = decayedBaseRate;
        emit BaseRateUpdated(decayedBaseRate);

        _updateLastFeeOpTime();
    }

    // --- Internal fee functions ---

    function _addCollateralToken(IERC20 _collateralToken, IPriceFeed _priceFeed, uint256 _positionsSize) internal {
        if (address(raftCollateralTokens[_collateralToken]) != address(0)) {
            revert CollateralTokenAlreadyAdded();
        }
        if (_positionsSize == 0) {
            revert SortedPositions.SizeCannotBeZero();
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

    /// @dev Update the last fee operation time only if time passed >= decay interval. This prevents base rate griefing.
    function _updateLastFeeOpTime() internal {
        uint256 timePassed = block.timestamp - lastFeeOperationTime;

        if (timePassed >= 1 minutes) {
            lastFeeOperationTime = block.timestamp;
            emit LastFeeOpTimeUpdated(block.timestamp);
        }
    }

    function _calcDecayedBaseRate() internal view returns (uint256) {
        uint256 minutesPassed = (block.timestamp - lastFeeOperationTime) / 1 minutes;
        uint256 decayFactor = MathUtils._decPow(MINUTE_DECAY_FACTOR, minutesPassed);

        return baseRate.mulDown(decayFactor);
    }

    // --- Helper functions ---

    function _triggerBorrowingFee(address _borrower, uint256 debtAmount, uint256 _maxFeePercentage)
        internal
        returns (uint256 rFee)
    {
        _decayBaseRateFromBorrowing(); // decay the baseRate state variable
        rFee = _getBorrowingFee(debtAmount);

        checkValidFee(rFee, debtAmount, _maxFeePercentage);

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
        returns (bool exists, address previousID, address nextID)
    {
        exists = sortedPositions[_collateralToken].nodes[_id].exists;
        previousID = sortedPositions[_collateralToken].nodes[_id].previousID;
        nextID = sortedPositions[_collateralToken].nodes[_id].nextID;
    }
}
