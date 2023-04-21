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

contract PositionManager is FeeCollector, IPositionManager {
    using SafeERC20 for IERC20;
    using Fixed256x18 for uint256;

    IRToken public immutable override rToken;

    IERC20Indexable public immutable override raftDebtToken;

    mapping(IERC20 collateralToken => IERC20Indexable raftCollateralToken) public override raftCollateralTokens;

    mapping(IERC20 collateralToken => IPriceFeed priceFeed) public override priceFeeds;

    mapping(address position => IERC20 collateralToken) public override collateralTokenForPosition;

    mapping(address delegate => bool isWhitelisted) public override globalDelegateWhitelist;
    mapping(address position => mapping(address delegate => bool isWhitelisted)) public override
        individualDelegateWhitelist;

    ISplitLiquidationCollateral public override splitLiquidationCollateral;

    /// @notice Half-life of 12h (720 min).
    /// @dev (1/2) = d^720 => d = (1/2)^(1/720)
    uint256 public constant MINUTE_DECAY_FACTOR = 999_037_758_833_783_000;

    uint256 public constant MIN_REDEMPTION_SPREAD = MathUtils._100_PERCENT / 10000 * 25; // 0.25%
    uint256 public constant MAX_REDEMPTION_SPREAD = MathUtils._100_PERCENT / 100 * 2; // 2%
    uint256 public constant override MAX_BORROWING_SPREAD = MathUtils._100_PERCENT / 100; // 1%
    uint256 public constant MAX_BORROWING_FEE = MathUtils._100_PERCENT / 100 * 5; // 5%

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
    /// @param position The borrower to check.
    /// @param collateralToken The collateral token to check.
    modifier onlyDepositedCollateralTokenOrNew(address position, IERC20 collateralToken) {
        if (
            collateralTokenForPosition[position] != IERC20(address(0))
                && collateralTokenForPosition[position] != collateralToken
        ) {
            revert PositionCollateralTokenMismatch();
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

    // --- Constructor ---

    /// @dev Initializes the position manager.
    /// @param delegates The delegates to whitelist.
    /// @param newSplitLiquidationCollateral The split liquidation collateral contract.
    constructor(address[] memory delegates, ISplitLiquidationCollateral newSplitLiquidationCollateral)
        FeeCollector(msg.sender)
    {
        rToken = new RToken(address(this), msg.sender);
        raftDebtToken = new ERC20Indexable(
            address(this),
            string(bytes.concat("Raft ", bytes(IERC20Metadata(address(rToken)).name()), " debt")),
            string(bytes.concat("r", bytes(IERC20Metadata(address(rToken)).symbol()), "-d"))
        );
        setRedemptionSpread(MathUtils._100_PERCENT / 100);
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

    function addCollateralToken(IERC20 _collateralToken, IPriceFeed _priceFeed) public override onlyOwner {
        if (address(raftCollateralTokens[_collateralToken]) != address(0)) {
            revert CollateralTokenAlreadyAdded();
        }

        raftCollateralTokens[_collateralToken] = new ERC20Indexable(
            address(this),
            string(bytes.concat("Raft ", bytes(IERC20Metadata(address(_collateralToken)).name()), " collateral")),
            string(bytes.concat("r", bytes(IERC20Metadata(address(_collateralToken)).symbol()), "-c"))
        );
        priceFeeds[_collateralToken] = _priceFeed;
        emit CollateralTokenAdded(_collateralToken, raftCollateralTokens[_collateralToken], _priceFeed);
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
        IERC20 collateralToken,
        address position,
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage
    ) external override {
        _managePosition(
            collateralToken,
            position,
            collateralChange,
            isCollateralIncrease,
            debtChange,
            isDebtIncrease,
            maxFeePercentage,
            true
        );
    }

    function managePosition(
        IERC20 collateralToken,
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage
    ) external override {
        _managePosition(
            collateralToken,
            msg.sender,
            collateralChange,
            isCollateralIncrease,
            debtChange,
            isDebtIncrease,
            maxFeePercentage,
            true
        );
    }

    /// @dev Manages the position on behalf of a given borrower.
    /// @param collateralToken The token the borrower used as collateral.
    /// @param position The address of the borrower.
    /// @param collateralChange The amount of collateral to add or remove.
    /// @param isCollateralIncrease True if the collateral is being increased, false otherwise.
    /// @param debtChange The amount of R to add or remove.
    /// @param isDebtIncrease True if the debt is being increased, false otherwise.
    /// @param maxFeePercentage The maximum fee percentage to pay for the position management.
    /// @param needsCollateralTransfer If collateral transfer is needed in case of collateral increase.
    /// It is used if the collateral is already transferred elsewhere, for example in whitelisted delegate.
    function _managePosition(
        IERC20 collateralToken,
        address position,
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        bool needsCollateralTransfer
    )
        internal
        collateralTokenExists(collateralToken)
        validMaxFeePercentageWhen(maxFeePercentage, isDebtIncrease)
        onlyDepositedCollateralTokenOrNew(position, collateralToken)
    {
        if (
            position != msg.sender && !globalDelegateWhitelist[msg.sender]
                && !individualDelegateWhitelist[position][msg.sender]
        ) {
            revert DelegateNotWhitelisted();
        }
        if (collateralChange == 0 && debtChange == 0) {
            revert NoCollateralOrDebtChange();
        }

        bool newPosition = (raftDebtToken.balanceOf(position) == 0);

        _adjustDebt(position, debtChange, isDebtIncrease, maxFeePercentage);
        _adjustCollateral(collateralToken, position, collateralChange, isCollateralIncrease, needsCollateralTransfer);

        uint256 positionDebt = raftDebtToken.balanceOf(position);
        uint256 positionCollateral = raftCollateralTokens[collateralToken].balanceOf(position);

        if (positionDebt == 0) {
            if (positionCollateral != 0) {
                revert InvalidPosition();
            }
            // position was closed, remove it
            _closePosition(collateralToken, position, false);
        } else {
            checkValidPosition(collateralToken, positionDebt, positionCollateral);

            if (newPosition) {
                collateralTokenForPosition[position] = collateralToken;
                emit PositionCreated(position);
            }
        }
    }

    /// @dev Adjusts the debt of a given borrower by burning or minting the corresponding amount of R and the Raft
    /// debt token. If the debt is being increased, the borrowing fee is also triggered.
    /// @param position The address of the borrower.
    /// @param debtChange The amount of R to add or remove. Must be positive.
    /// @param isDebtIncrease True if the debt is being increased, false otherwise.
    /// @param maxFeePercentage The maximum fee percentage.
    function _adjustDebt(address position, uint256 debtChange, bool isDebtIncrease, uint256 maxFeePercentage)
        internal
    {
        if (debtChange == 0) {
            return;
        }

        if (isDebtIncrease) {
            uint256 totalDebtChange = debtChange + _triggerBorrowingFee(position, debtChange, maxFeePercentage);
            raftDebtToken.mint(position, totalDebtChange);
            totalDebt += totalDebtChange;
            rToken.mint(msg.sender, debtChange);
        } else {
            totalDebt -= debtChange;
            raftDebtToken.burn(position, debtChange);
            rToken.burn(msg.sender, debtChange);
        }

        emit DebtChanged(position, debtChange, isDebtIncrease);
    }

    /// @dev Adjusts the collateral of a given borrower by burning or minting the corresponding amount of Raft
    /// collateral token and transferring the corresponding amount of collateral token.
    /// @param collateralToken The token the borrower used as collateral.
    /// @param position The address of the borrower.
    /// @param collateralChange The amount of collateral to add or remove. Must be positive.
    /// @param isCollateralIncrease True if the collateral is being increased, false otherwise.
    /// @param needsCollateralTransfer True if the collateral token needs to be transferred, false otherwise.
    function _adjustCollateral(
        IERC20 collateralToken,
        address position,
        uint256 collateralChange,
        bool isCollateralIncrease,
        bool needsCollateralTransfer
    ) internal {
        if (collateralChange == 0) {
            return;
        }

        if (isCollateralIncrease) {
            raftCollateralTokens[collateralToken].mint(position, collateralChange);
            if (needsCollateralTransfer) {
                collateralToken.safeTransferFrom(msg.sender, address(this), collateralChange);
            }
        } else {
            raftCollateralTokens[collateralToken].burn(position, collateralChange);
            if (needsCollateralTransfer) {
                collateralToken.safeTransfer(msg.sender, collateralChange);
            }
        }

        emit CollateralChanged(position, collateralChange, isCollateralIncrease);
    }

    function whitelistDelegate(address delegate) external override {
        if (delegate == address(0)) {
            revert InvalidDelegateAddress();
        }
        individualDelegateWhitelist[msg.sender][delegate] = true;
    }

    // --- Position Liquidation functions ---

    function liquidate(IERC20 collateralToken, address position) external override {
        uint256 price = priceFeeds[collateralToken].fetchPrice();
        uint256 icr = getCurrentICR(collateralToken, position, price);
        if (icr >= MathUtils.MCR) {
            revert NothingToLiquidate();
        }

        uint256 entirePositionDebt = raftDebtToken.balanceOf(position);
        uint256 entirePositionCollateral = raftCollateralTokens[collateralToken].balanceOf(position);
        bool isRedistribution = icr <= MathUtils._100_PERCENT;

        (uint256 collateralLiquidationFee, uint256 collateralToSendToLiquidator) =
            splitLiquidationCollateral.split(entirePositionCollateral, entirePositionDebt, price, isRedistribution);

        if (!isRedistribution) {
            rToken.burn(msg.sender, entirePositionDebt);
            totalDebt -= entirePositionDebt;
            // Collateral is sent to protocol as a fee only in case of liquidation
            collateralToken.transfer(feeRecipient, collateralLiquidationFee);
        }

        collateralToken.transfer(msg.sender, collateralToSendToLiquidator);

        _closePosition(collateralToken, position, true);

        _updateDebtAndCollateralIndex(collateralToken);

        emit Liquidation(
            msg.sender,
            position,
            collateralToken,
            entirePositionDebt,
            entirePositionCollateral,
            collateralToSendToLiquidator,
            collateralLiquidationFee,
            isRedistribution
        );
    }

    function redeemCollateral(IERC20 collateralToken, uint256 debtAmount, uint256 maxFeePercentage)
        external
        override
    {
        if (maxFeePercentage < MIN_REDEMPTION_SPREAD || maxFeePercentage > MathUtils._100_PERCENT) {
            revert MaxFeePercentageOutOfRange();
        }
        if (debtAmount == 0) {
            revert AmountIsZero();
        }

        uint256 price = priceFeeds[collateralToken].fetchPrice();
        uint256 collateralToRedeem = debtAmount.divDown(price);

        // Decay the baseRate due to time passed, and then increase it according to the size of this redemption.
        // Use the saved total R supply value, from before it was reduced by the redemption.
        _updateBaseRateFromRedemption(collateralToRedeem, price, rToken.totalSupply());

        // Calculate the redemption fee
        uint256 redemptionFee = _calcRedemptionFee(getRedemptionRate(), collateralToRedeem);

        checkValidFee(redemptionFee, collateralToRedeem, maxFeePercentage);

        // Send the redemption fee to the recipient
        collateralToken.safeTransfer(feeRecipient, redemptionFee);

        emit Redemption(debtAmount, collateralToRedeem, redemptionFee);

        // Burn the total R that is cancelled with debt, and send the redeemed collateral to msg.sender
        rToken.burn(msg.sender, debtAmount);
        totalDebt -= debtAmount;

        // Send collateral to account
        collateralToken.safeTransfer(msg.sender, collateralToRedeem - redemptionFee);

        _updateDebtAndCollateralIndex(collateralToken);
    }

    // --- Helper functions ---

    /// @dev Returns the nominal collateral ratio (ICR) of a given position, without the price. Takes the position's
    /// pending collateral and debt rewards from redistributions into account.
    function getNominalICR(IERC20 collateralToken, address position) public view override returns (uint256 nicr) {
        return MathUtils._computeNominalCR(
            raftCollateralTokens[collateralToken].balanceOf(position), raftDebtToken.balanceOf(position)
        );
    }

    /// @dev Returns the current collateral ratio (ICR) of a given position. Takes the position's pending collateral and
    /// debt rewards from redistributions into account.
    function getCurrentICR(IERC20 collateralToken, address position, uint256 price)
        public
        view
        override
        returns (uint256)
    {
        return MathUtils._computeCR(
            raftCollateralTokens[collateralToken].balanceOf(position), raftDebtToken.balanceOf(position), price
        );
    }

    /// @dev Updates debt and collateral indexes for a given collateral token.
    /// @param collateralToken The collateral token for which to update the indexes.
    function _updateDebtAndCollateralIndex(IERC20 collateralToken) internal {
        raftDebtToken.setIndex(totalDebt);
        raftCollateralTokens[collateralToken].setIndex(collateralToken.balanceOf(address(this)));
    }

    function _closePosition(IERC20 collateralToken, address position, bool burnTokens) internal {
        collateralTokenForPosition[position] = IERC20(address(0));

        if (burnTokens) {
            raftDebtToken.burn(position, type(uint256).max);
            raftCollateralTokens[collateralToken].burn(position, type(uint256).max);
        }
        emit PositionClosed(position);
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

    function _triggerBorrowingFee(address position, uint256 debtAmount, uint256 _maxFeePercentage)
        internal
        returns (uint256 rFee)
    {
        _decayBaseRateFromBorrowing(); // decay the baseRate state variable
        rFee = _getBorrowingFee(debtAmount);

        checkValidFee(rFee, debtAmount, _maxFeePercentage);

        if (rFee > 0) {
            rToken.mint(feeRecipient, rFee);
            emit RBorrowingFeePaid(position, rFee);
        }
    }

    function checkValidPosition(IERC20 _collateralToken, uint256 positionDebt, uint256 positionCollateral) internal {
        if (positionDebt < splitLiquidationCollateral.LOW_TOTAL_DEBT()) {
            revert NetDebtBelowMinimum(positionDebt);
        }

        uint256 newICR =
            MathUtils._computeCR(positionCollateral, positionDebt, priceFeeds[_collateralToken].fetchPrice());
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
}
