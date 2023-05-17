// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { ERC20PermitSignature, PermitHelper } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { MathUtils } from "./Dependencies/MathUtils.sol";
import { IERC20Indexable } from "./Interfaces/IERC20Indexable.sol";
import { IPositionManager } from "./Interfaces/IPositionManager.sol";
import { IPriceFeed } from "./Interfaces/IPriceFeed.sol";
import { ISplitLiquidationCollateral } from "./Interfaces/ISplitLiquidationCollateral.sol";
import { ERC20Indexable } from "./ERC20Indexable.sol";
import { FeeCollector } from "./FeeCollector.sol";
import { RToken, IRToken } from "./RToken.sol";

contract PositionManager is FeeCollector, IPositionManager {
    // --- Types ---

    using SafeERC20 for IERC20;
    using Fixed256x18 for uint256;

    // --- Constants ---

    uint256 public constant override MINUTE_DECAY_FACTOR = 999_037_758_833_783_000;

    uint256 public constant override MIN_REDEMPTION_SPREAD = MathUtils._100_PERCENT / 10_000 * 5; // 0.05%
    uint256 public constant override MAX_REDEMPTION_SPREAD = MathUtils._100_PERCENT;
    uint256 public constant override MAX_BORROWING_SPREAD = MathUtils._100_PERCENT / 100; // 1%
    uint256 public constant override MAX_BORROWING_RATE = MathUtils._100_PERCENT / 100 * 5; // 5%

    uint256 public constant override BETA = 2;

    // --- Immutables ---

    IRToken public immutable override rToken;
    IERC20Indexable public immutable override raftDebtToken;

    // --- Variables ---

    mapping(IERC20 collateralToken => RaftCollateralTokenInfo tokenInfo) public override raftCollateralTokens;

    mapping(IERC20 collateralToken => IPriceFeed priceFeed) public override priceFeeds;

    mapping(address position => IERC20 collateralToken) public override collateralTokenForPosition;

    mapping(address position => mapping(address delegate => bool isWhitelisted)) public override isDelegateWhitelisted;

    ISplitLiquidationCollateral public override splitLiquidationCollateral;

    uint256 public override borrowingSpread;
    uint256 public override redemptionSpread;
    uint256 public override baseRate;
    uint256 public override redemptionRebate;

    uint256 public override lastFeeOperationTime;

    uint256 private _totalDebt;

    // --- Modifiers ---

    /// @dev Checks if the collateral token has been added to the position manager, or reverts otherwise.
    /// @param collateralToken The collateral token to check.
    modifier collateralTokenExists(IERC20 collateralToken) {
        if (address(raftCollateralTokens[collateralToken].token) == address(0)) {
            revert CollateralTokenNotAdded();
        }
        _;
    }

    /// @dev Checks if the collateral token has enabled, or reverts otherwise. When the condition is false, the check
    /// is skipped.
    /// @param collateralToken The collateral token to check.
    /// @param condition If true, the check will be performed.
    modifier onlyEnabledCollateralTokenWhen(IERC20 collateralToken, bool condition) {
        if (condition && !raftCollateralTokens[collateralToken].isEnabled) {
            revert CollateralTokenDisabled();
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
    /// @param maxFeePercentage The max fee percentage to check.
    /// @param condition If true, the check will be performed.
    modifier validMaxFeePercentageWhen(uint256 maxFeePercentage, bool condition) {
        if (condition && (maxFeePercentage < borrowingSpread || maxFeePercentage > MathUtils._100_PERCENT)) {
            revert InvalidMaxFeePercentage();
        }
        _;
    }

    // --- Constructor ---

    /// @dev Initializes the position manager.
    /// @param newSplitLiquidationCollateral The split liquidation collateral contract.
    constructor(ISplitLiquidationCollateral newSplitLiquidationCollateral) FeeCollector(msg.sender) {
        rToken = new RToken(address(this), msg.sender);
        raftDebtToken = new ERC20Indexable(
            address(this),
            string(bytes.concat("Raft ", bytes(IERC20Metadata(address(rToken)).name()), " debt")),
            string(bytes.concat("r", bytes(IERC20Metadata(address(rToken)).symbol()), "-d"))
        );
        setRedemptionSpread(MathUtils._100_PERCENT);
        setRedemptionRebate(MathUtils._100_PERCENT);
        setSplitLiquidationCollateral(newSplitLiquidationCollateral);

        emit PositionManagerDeployed(rToken, raftDebtToken, msg.sender);
    }

    // --- External functions ---

    function managePosition(
        IERC20 collateralToken,
        address position,
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        ERC20PermitSignature calldata permitSignature
    )
        external
        override
        collateralTokenExists(collateralToken)
        validMaxFeePercentageWhen(maxFeePercentage, isDebtIncrease)
        onlyDepositedCollateralTokenOrNew(position, collateralToken)
        onlyEnabledCollateralTokenWhen(collateralToken, isDebtIncrease && debtChange > 0)
        returns (uint256 actualCollateralChange, uint256 actualDebtChange)
    {
        if (position != msg.sender && !isDelegateWhitelisted[position][msg.sender]) {
            revert DelegateNotWhitelisted();
        }
        if (collateralChange == 0 && debtChange == 0) {
            revert NoCollateralOrDebtChange();
        }
        if (collateralChange == type(uint256).max) {
            revert MaxCollateralChangeExceeded();
        }
        
        if (address(permitSignature.token) == address(collateralToken)) {
            PermitHelper.applyPermit(permitSignature, msg.sender, address(this));
        }

        uint256 debtBefore = raftDebtToken.balanceOf(position);
        if (!isDebtIncrease && (debtChange == type(uint256).max || (debtBefore != 0 && debtChange == debtBefore))) {
            if (collateralChange != 0 || isCollateralIncrease) {
                revert WrongCollateralParamsForFullRepayment();
            }
            collateralChange = raftCollateralTokens[collateralToken].token.balanceOf(position);
            debtChange = debtBefore;
        }

        _adjustDebt(position, debtChange, isDebtIncrease, maxFeePercentage);
        _adjustCollateral(collateralToken, position, collateralChange, isCollateralIncrease);

        uint256 positionDebt = raftDebtToken.balanceOf(position);
        uint256 positionCollateral = raftCollateralTokens[collateralToken].token.balanceOf(position);

        if (positionDebt == 0) {
            if (positionCollateral != 0) {
                revert InvalidPosition();
            }
            // position was closed, remove it
            _closePosition(collateralToken, position, false);
        } else {
            _checkValidPosition(collateralToken, positionDebt, positionCollateral);

            if (debtBefore == 0) {
                collateralTokenForPosition[position] = collateralToken;
                emit PositionCreated(position, collateralToken);
            }
        }
        return (collateralChange, debtChange);
    }

    function liquidate(address position) external override {
        IERC20 collateralToken = collateralTokenForPosition[position];
        if (address(collateralToken) == address(0)) {
            revert NothingToLiquidate();
        }
        (uint256 price,) = priceFeeds[collateralToken].fetchPrice();
        uint256 entirePositionCollateral = raftCollateralTokens[collateralToken].token.balanceOf(position);
        uint256 entirePositionDebt = raftDebtToken.balanceOf(position);
        uint256 icr = MathUtils._computeCR(entirePositionCollateral, entirePositionDebt, price);
        if (icr >= MathUtils.MCR) {
            revert NothingToLiquidate();
        }

        if (entirePositionDebt == raftDebtToken.totalSupply()) {
            revert CannotLiquidateLastPosition();
        }
        bool isRedistribution = icr <= MathUtils._100_PERCENT;

        (uint256 collateralLiquidationFee, uint256 collateralToSendToLiquidator) =
            splitLiquidationCollateral.split(entirePositionCollateral, entirePositionDebt, price, isRedistribution);

        if (!isRedistribution) {
            rToken.burn(msg.sender, entirePositionDebt);
            _totalDebt -= entirePositionDebt;
            emit TotalDebtChanged(_totalDebt);

            // Collateral is sent to protocol as a fee only in case of liquidation
            collateralToken.safeTransfer(feeRecipient, collateralLiquidationFee);
        }

        collateralToken.safeTransfer(msg.sender, collateralToSendToLiquidator);

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

    function redeemCollateral(
        IERC20 collateralToken,
        uint256 debtAmount,
        uint256 maxFeePercentage
    )
        external
        override
    {
        if (maxFeePercentage < MIN_REDEMPTION_SPREAD || maxFeePercentage > MathUtils._100_PERCENT) {
            revert MaxFeePercentageOutOfRange();
        }
        if (debtAmount == 0) {
            revert AmountIsZero();
        }

        (uint256 price, uint256 deviation) = priceFeeds[collateralToken].fetchPrice();
        uint256 collateralToRedeem = debtAmount.divDown(price);

        // Decay the baseRate due to time passed, and then increase it according to the size of this redemption.
        // Use the saved total R supply value, from before it was reduced by the redemption.
        _updateBaseRateFromRedemption(collateralToRedeem, price, rToken.totalSupply());

        // Calculate the redemption fee
        uint256 redemptionFee = getRedemptionFee(collateralToRedeem, deviation);
        uint256 rebate = redemptionFee.mulDown(redemptionRebate);

        _checkValidFee(redemptionFee, collateralToRedeem, maxFeePercentage);

        // Send the redemption fee to the recipient
        collateralToken.safeTransfer(feeRecipient, redemptionFee - rebate);

        // Burn the total R that is cancelled with debt, and send the redeemed collateral to msg.sender
        rToken.burn(msg.sender, debtAmount);
        _totalDebt -= debtAmount;
        emit TotalDebtChanged(_totalDebt);

        // Send collateral to account
        collateralToken.safeTransfer(msg.sender, collateralToRedeem - redemptionFee);

        _updateDebtAndCollateralIndex(collateralToken);

        emit Redemption(msg.sender, debtAmount, collateralToRedeem, redemptionFee, rebate);
    }

    function whitelistDelegate(address delegate, bool whitelisted) external override {
        if (delegate == address(0)) {
            revert InvalidDelegateAddress();
        }
        isDelegateWhitelisted[msg.sender][delegate] = whitelisted;

        emit DelegateWhitelisted(msg.sender, delegate, whitelisted);
    }

    function setBorrowingSpread(uint256 newBorrowingSpread) external override onlyOwner {
        if (newBorrowingSpread > MAX_BORROWING_SPREAD) {
            revert BorrowingSpreadExceedsMaximum();
        }
        borrowingSpread = newBorrowingSpread;
        emit BorrowingSpreadUpdated(newBorrowingSpread);
    }

    function setRedemptionRebate(uint256 newRedemptionRebate) public override onlyOwner {
        if (newRedemptionRebate > MathUtils._100_PERCENT) {
            revert RedemptionRebateExceedsMaximum();
        }
        redemptionRebate = newRedemptionRebate;
        emit RedemptionRebateUpdated(newRedemptionRebate);
    }

    function getRedemptionFeeWithDecay(uint256 collateralAmount)
        external
        view
        override
        returns (uint256 redemptionFee)
    {
        redemptionFee = getRedemptionRateWithDecay().mulDown(collateralAmount);
        if (redemptionFee >= collateralAmount) {
            revert FeeEatsUpAllReturnedCollateral();
        }
    }

    // --- Public functions ---

    function addCollateralToken(IERC20 collateralToken, IPriceFeed priceFeed) public override onlyOwner {
        if (address(collateralToken) == address(0)) {
            revert CollateralTokenAddressCannotBeZero();
        }
        if (address(priceFeed) == address(0)) {
            revert PriceFeedAddressCannotBeZero();
        }
        if (address(raftCollateralTokens[collateralToken].token) != address(0)) {
            revert CollateralTokenAlreadyAdded();
        }

        RaftCollateralTokenInfo memory raftCollateralTokenInfo;
        raftCollateralTokenInfo.token = new ERC20Indexable(
            address(this),
            string(bytes.concat("Raft ", bytes(IERC20Metadata(address(collateralToken)).name()), " collateral")),
            string(bytes.concat("r", bytes(IERC20Metadata(address(collateralToken)).symbol()), "-c"))
        );
        raftCollateralTokenInfo.isEnabled = true;

        raftCollateralTokens[collateralToken] = raftCollateralTokenInfo;
        priceFeeds[collateralToken] = priceFeed;

        emit CollateralTokenAdded(collateralToken, raftCollateralTokens[collateralToken].token, priceFeed);
    }

    function modifyCollateralToken(
        IERC20 collateralToken,
        bool isEnabled
    )
        public
        override
        onlyOwner
        collateralTokenExists(collateralToken)
    {
        bool previousIsEnabled = raftCollateralTokens[collateralToken].isEnabled;
        raftCollateralTokens[collateralToken].isEnabled = isEnabled;

        if (previousIsEnabled != isEnabled) {
            emit CollateralTokenModified(collateralToken, raftCollateralTokens[collateralToken].token, isEnabled);
        }
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

    function setRedemptionSpread(uint256 newRedemptionSpread) public override onlyOwner {
        if (newRedemptionSpread < MIN_REDEMPTION_SPREAD || newRedemptionSpread > MAX_REDEMPTION_SPREAD) {
            revert RedemptionSpreadOutOfRange();
        }
        redemptionSpread = newRedemptionSpread;
        emit RedemptionSpreadUpdated(newRedemptionSpread);
    }

    function getRedemptionRate() public view override returns (uint256) {
        return _calcRedemptionRate(baseRate);
    }

    function getRedemptionRateWithDecay() public view override returns (uint256) {
        return _calcRedemptionRate(_calcDecayedBaseRate());
    }

    function getRedemptionFee(
        uint256 collateralAmount,
        uint256 priceDeviation
    )
        public
        view
        override
        returns (uint256)
    {
        return Math.min(getRedemptionRate() + priceDeviation, MathUtils._100_PERCENT).mulDown(collateralAmount);
    }

    function getBorrowingRate() public view override returns (uint256) {
        return _calcBorrowingRate(baseRate);
    }

    function getBorrowingRateWithDecay() public view override returns (uint256) {
        return _calcBorrowingRate(_calcDecayedBaseRate());
    }

    function getBorrowingFee(uint256 debtAmount) public view override returns (uint256) {
        return getBorrowingRate().mulDown(debtAmount);
    }

    // --- Helper functions ---

    /// @dev Adjusts the debt of a given borrower by burning or minting the corresponding amount of R and the Raft
    /// debt token. If the debt is being increased, the borrowing fee is also triggered.
    /// @param position The address of the borrower.
    /// @param debtChange The amount of R to add or remove. Must be positive.
    /// @param isDebtIncrease True if the debt is being increased, false otherwise.
    /// @param maxFeePercentage The maximum fee percentage.
    function _adjustDebt(
        address position,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage
    )
        internal
    {
        if (debtChange == 0) {
            return;
        }

        if (isDebtIncrease) {
            uint256 totalDebtChange = debtChange + _triggerBorrowingFee(position, debtChange, maxFeePercentage);
            raftDebtToken.mint(position, totalDebtChange);
            _totalDebt += totalDebtChange;
            rToken.mint(msg.sender, debtChange);
        } else {
            _totalDebt -= debtChange;
            raftDebtToken.burn(position, debtChange);
            rToken.burn(msg.sender, debtChange);
        }

        emit DebtChanged(position, debtChange, isDebtIncrease);
        emit TotalDebtChanged(_totalDebt);
    }

    /// @dev Adjusts the collateral of a given borrower by burning or minting the corresponding amount of Raft
    /// collateral token and transferring the corresponding amount of collateral token.
    /// @param collateralToken The token the borrower used as collateral.
    /// @param position The address of the borrower.
    /// @param collateralChange The amount of collateral to add or remove. Must be positive.
    /// @param isCollateralIncrease True if the collateral is being increased, false otherwise.
    function _adjustCollateral(
        IERC20 collateralToken,
        address position,
        uint256 collateralChange,
        bool isCollateralIncrease
    )
        internal
    {
        if (collateralChange == 0) {
            return;
        }

        if (isCollateralIncrease) {
            raftCollateralTokens[collateralToken].token.mint(position, collateralChange);
            collateralToken.safeTransferFrom(msg.sender, address(this), collateralChange);
        } else {
            raftCollateralTokens[collateralToken].token.burn(position, collateralChange);
            collateralToken.safeTransfer(msg.sender, collateralChange);
        }

        emit CollateralChanged(position, collateralChange, isCollateralIncrease);
    }

    /// @dev Updates debt and collateral indexes for a given collateral token.
    /// @param collateralToken The collateral token for which to update the indexes.
    function _updateDebtAndCollateralIndex(IERC20 collateralToken) internal {
        raftDebtToken.setIndex(_totalDebt);
        raftCollateralTokens[collateralToken].token.setIndex(collateralToken.balanceOf(address(this)));
    }

    function _closePosition(IERC20 collateralToken, address position, bool burnTokens) internal {
        collateralTokenForPosition[position] = IERC20(address(0));

        if (burnTokens) {
            raftDebtToken.burn(position, type(uint256).max);
            raftCollateralTokens[collateralToken].token.burn(position, type(uint256).max);
        }
        emit PositionClosed(position, collateralToken);
    }

    // --- Borrowing & redemption fee helper functions ---

    /// @dev Updates the base rate from a redemption operation. Impacts on the base rate:
    /// 1. decays the base rate based on time passed since last redemption or R borrowing operation,
    /// 2. increases the base rate based on the amount redeemed, as a proportion of total supply.
    function _updateBaseRateFromRedemption(
        uint256 collateralDrawn,
        uint256 price,
        uint256 totalDebtSupply
    )
        internal
        returns (uint256)
    {
        uint256 decayedBaseRate = _calcDecayedBaseRate();

        /* Convert the drawn collateral back to R at face value rate (1 R:1 USD), in order to get
        * the fraction of total supply that was redeemed at face value. */
        uint256 redeemedFraction = collateralDrawn * price / totalDebtSupply;

        uint256 newBaseRate = decayedBaseRate + redeemedFraction / BETA;
        newBaseRate = Math.min(newBaseRate, MathUtils._100_PERCENT); // cap baseRate at a maximum of 100%
        assert(newBaseRate > 0); // Base rate is always non-zero after redemption

        // Update the baseRate state variable
        baseRate = newBaseRate;
        emit BaseRateUpdated(newBaseRate);

        _updateLastFeeOpTime();

        return newBaseRate;
    }

    function _calcRedemptionRate(uint256 baseRate_) internal view returns (uint256) {
        return baseRate_ + redemptionSpread;
    }

    function _calcBorrowingRate(uint256 baseRate_) internal view returns (uint256) {
        return Math.min(borrowingSpread + baseRate_, MAX_BORROWING_RATE);
    }

    /// @dev Updates the base rate based on time elapsed since the last redemption or R borrowing operation.
    function _decayBaseRateFromBorrowing() internal {
        uint256 decayedBaseRate = _calcDecayedBaseRate();
        assert(decayedBaseRate <= MathUtils._100_PERCENT); // The baseRate can decay to 0

        baseRate = decayedBaseRate;
        emit BaseRateUpdated(decayedBaseRate);

        _updateLastFeeOpTime();
    }

    /// @dev Update the last fee operation time only if time passed >= decay interval. This prevents base rate
    /// griefing.
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

    function _triggerBorrowingFee(
        address position,
        uint256 debtAmount,
        uint256 maxFeePercentage
    )
        internal
        returns (uint256 borrowingFee)
    {
        _decayBaseRateFromBorrowing(); // decay the baseRate state variable
        borrowingFee = getBorrowingFee(debtAmount);

        _checkValidFee(borrowingFee, debtAmount, maxFeePercentage);

        if (borrowingFee > 0) {
            rToken.mint(feeRecipient, borrowingFee);
            emit RBorrowingFeePaid(position, borrowingFee);
        }
    }

    // --- Validation check helper functions ---

    function _checkValidPosition(IERC20 collateralToken, uint256 positionDebt, uint256 positionCollateral) internal {
        if (positionDebt < splitLiquidationCollateral.LOW_TOTAL_DEBT()) {
            revert NetDebtBelowMinimum(positionDebt);
        }

        (uint256 price,) = priceFeeds[collateralToken].fetchPrice();
        uint256 newICR = MathUtils._computeCR(positionCollateral, positionDebt, price);
        if (newICR < MathUtils.MCR) {
            revert NewICRLowerThanMCR(newICR);
        }
    }

    function _checkValidFee(uint256 fee, uint256 amount, uint256 maxFeePercentage) internal pure {
        uint256 feePercentage = fee.divDown(amount);

        if (feePercentage > maxFeePercentage) {
            revert FeeExceedsMaxFee(fee, amount, maxFeePercentage);
        }
    }
}
