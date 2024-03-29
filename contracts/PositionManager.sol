// SPDX-License-Identifier: BUSL-1.1
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

/// @dev Implementation of Position Manager. Current implementation does not support rebasing tokens as collateral.
contract PositionManager is FeeCollector, IPositionManager {
    // --- Types ---

    using SafeERC20 for IERC20;
    using Fixed256x18 for uint256;

    // --- Constants ---

    uint256 public constant override MINUTE_DECAY_FACTOR = 999_037_758_833_783_000;

    uint256 public constant override MAX_BORROWING_SPREAD = MathUtils._100_PERCENT / 100; // 1%
    uint256 public constant override MAX_BORROWING_RATE = MathUtils._100_PERCENT / 100 * 5; // 5%

    uint256 public constant override BETA = 2;

    // --- Immutables ---

    IRToken public immutable override rToken;

    // --- Variables ---

    mapping(address position => IERC20 collateralToken) public override collateralTokenForPosition;

    mapping(address position => mapping(address delegate => bool isWhitelisted)) public override isDelegateWhitelisted;

    mapping(IERC20 collateralToken => CollateralTokenInfo collateralTokenInfo) public override collateralInfo;

    // --- Modifiers ---

    /// @dev Checks if the collateral token has been added to the position manager, or reverts otherwise.
    /// @param collateralToken The collateral token to check.
    modifier collateralTokenExists(IERC20 collateralToken) {
        if (address(collateralInfo[collateralToken].collateralToken) == address(0)) {
            revert CollateralTokenNotAdded();
        }
        _;
    }

    /// @dev Checks if the collateral token has enabled, or reverts otherwise. When the condition is false, the check
    /// is skipped.
    /// @param collateralToken The collateral token to check.
    /// @param condition If true, the check will be performed.
    modifier onlyEnabledCollateralTokenWhen(IERC20 collateralToken, bool condition) {
        if (condition && !collateralInfo[collateralToken].isEnabled) {
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
        if (condition && maxFeePercentage > MathUtils._100_PERCENT) {
            revert InvalidMaxFeePercentage();
        }
        _;
    }

    // --- Constructor ---

    /// @dev Initializes the position manager.
    constructor(address rToken_) FeeCollector(msg.sender) {
        rToken = rToken_ == address(0) ? new RToken(address(this), msg.sender) : IRToken(rToken_);
        emit PositionManagerDeployed(rToken, msg.sender);
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
        public
        virtual
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
        if (address(permitSignature.token) == address(collateralToken)) {
            PermitHelper.applyPermit(permitSignature, msg.sender, address(this));
        }

        CollateralTokenInfo storage collateralTokenInfo = collateralInfo[collateralToken];
        IERC20Indexable raftCollateralToken = collateralTokenInfo.collateralToken;
        IERC20Indexable raftDebtToken = collateralTokenInfo.debtToken;

        uint256 debtBefore = raftDebtToken.balanceOf(position);
        if (!isDebtIncrease && (debtChange == type(uint256).max || (debtBefore != 0 && debtChange == debtBefore))) {
            if (collateralChange != 0 || isCollateralIncrease) {
                revert WrongCollateralParamsForFullRepayment();
            }
            collateralChange = raftCollateralToken.balanceOf(position);
            debtChange = debtBefore;
        }

        _adjustDebt(position, collateralToken, raftDebtToken, debtChange, isDebtIncrease, maxFeePercentage);
        _adjustCollateral(collateralToken, raftCollateralToken, position, collateralChange, isCollateralIncrease);

        uint256 positionDebt = raftDebtToken.balanceOf(position);
        uint256 positionCollateral = raftCollateralToken.balanceOf(position);

        if (positionDebt == 0) {
            if (positionCollateral != 0) {
                revert InvalidPosition();
            }
            // position was closed, remove it
            _closePosition(raftCollateralToken, raftDebtToken, position, false);
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
        CollateralTokenInfo storage collateralTokenInfo = collateralInfo[collateralToken];
        IERC20Indexable raftCollateralToken = collateralTokenInfo.collateralToken;
        IERC20Indexable raftDebtToken = collateralTokenInfo.debtToken;
        ISplitLiquidationCollateral splitLiquidation = collateralTokenInfo.splitLiquidation;

        if (address(collateralToken) == address(0)) {
            revert NothingToLiquidate();
        }
        (uint256 price,) = collateralTokenInfo.priceFeed.fetchPrice();
        uint256 entireCollateral = raftCollateralToken.balanceOf(position);
        uint256 entireDebt = raftDebtToken.balanceOf(position);
        uint256 icr = MathUtils._computeCR(entireCollateral, entireDebt, price);

        if (icr >= splitLiquidation.MCR()) {
            revert NothingToLiquidate();
        }

        uint256 totalDebt = raftDebtToken.totalSupply();
        if (entireDebt == totalDebt) {
            revert CannotLiquidateLastPosition();
        }
        bool isRedistribution = icr <= MathUtils._100_PERCENT;

        // prettier: ignore
        (uint256 collateralLiquidationFee, uint256 collateralToSendToLiquidator) =
            splitLiquidation.split(entireCollateral, entireDebt, price, isRedistribution);

        if (!isRedistribution) {
            _burnRTokens(msg.sender, entireDebt);
            totalDebt -= entireDebt;

            // Collateral is sent to protocol as a fee only in case of liquidation
            collateralToken.safeTransfer(feeRecipient, collateralLiquidationFee);
        }

        collateralToken.safeTransfer(msg.sender, collateralToSendToLiquidator);

        _closePosition(raftCollateralToken, raftDebtToken, position, true);

        _updateDebtAndCollateralIndex(collateralToken, raftCollateralToken, raftDebtToken, totalDebt);

        emit Liquidation(
            msg.sender,
            position,
            collateralToken,
            entireDebt,
            entireCollateral,
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
        public
        virtual
        override
    {
        if (maxFeePercentage > MathUtils._100_PERCENT) {
            revert MaxFeePercentageOutOfRange();
        }
        if (debtAmount == 0) {
            revert AmountIsZero();
        }
        IERC20Indexable raftDebtToken = collateralInfo[collateralToken].debtToken;

        uint256 newTotalDebt = raftDebtToken.totalSupply() - debtAmount;
        uint256 lowTotalDebt = collateralInfo[collateralToken].splitLiquidation.LOW_TOTAL_DEBT();
        if (newTotalDebt < lowTotalDebt) {
            revert TotalDebtCannotBeLowerThanMinDebt(collateralToken, newTotalDebt);
        }

        (uint256 price, uint256 deviation) = collateralInfo[collateralToken].priceFeed.fetchPrice();
        uint256 collateralToRedeem = debtAmount.divDown(price);
        uint256 totalCollateral = collateralToken.balanceOf(address(this));
        if (
            totalCollateral - collateralToRedeem == 0
                || totalCollateral - collateralToRedeem < lowTotalDebt.divDown(price)
        ) {
            revert TotalCollateralCannotBeLowerThanMinCollateral(
                collateralToken, totalCollateral - collateralToRedeem, lowTotalDebt.divDown(price)
            );
        }

        // Decay the baseRate due to time passed, and then increase it according to the size of this redemption.
        // Use the saved total R supply value, from before it was reduced by the redemption.
        _updateBaseRateFromRedemption(collateralToken, collateralToRedeem, price, rToken.totalSupply());

        // Calculate the redemption fee
        uint256 redemptionFee = getRedemptionFee(collateralToken, collateralToRedeem, deviation);
        uint256 rebate = redemptionFee.mulDown(collateralInfo[collateralToken].redemptionRebate);

        _checkValidFee(redemptionFee, collateralToRedeem, maxFeePercentage);

        // Send the redemption fee to the recipient
        collateralToken.safeTransfer(feeRecipient, redemptionFee - rebate);

        // Burn the total R that is cancelled with debt, and send the redeemed collateral to msg.sender
        _burnRTokens(msg.sender, debtAmount);

        // Send collateral to account
        collateralToken.safeTransfer(msg.sender, collateralToRedeem - redemptionFee);

        _updateDebtAndCollateralIndex(
            collateralToken, collateralInfo[collateralToken].collateralToken, raftDebtToken, newTotalDebt
        );

        emit Redemption(msg.sender, debtAmount, collateralToRedeem, redemptionFee, rebate);
    }

    function whitelistDelegate(address delegate, bool whitelisted) external override {
        if (delegate == address(0)) {
            revert InvalidDelegateAddress();
        }
        isDelegateWhitelisted[msg.sender][delegate] = whitelisted;

        emit DelegateWhitelisted(msg.sender, delegate, whitelisted);
    }

    function setBorrowingSpread(IERC20 collateralToken, uint256 newBorrowingSpread) external override onlyOwner {
        if (newBorrowingSpread > MAX_BORROWING_SPREAD) {
            revert BorrowingSpreadExceedsMaximum();
        }
        collateralInfo[collateralToken].borrowingSpread = newBorrowingSpread;
        emit BorrowingSpreadUpdated(newBorrowingSpread);
    }

    function setRedemptionRebate(IERC20 collateralToken, uint256 newRedemptionRebate) public override onlyOwner {
        if (newRedemptionRebate > MathUtils._100_PERCENT) {
            revert RedemptionRebateExceedsMaximum();
        }
        collateralInfo[collateralToken].redemptionRebate = newRedemptionRebate;
        emit RedemptionRebateUpdated(newRedemptionRebate);
    }

    function getRedemptionFeeWithDecay(
        IERC20 collateralToken,
        uint256 collateralAmount
    )
        external
        view
        override
        returns (uint256 redemptionFee)
    {
        redemptionFee = getRedemptionRateWithDecay(collateralToken).mulDown(collateralAmount);
        if (redemptionFee >= collateralAmount) {
            revert FeeEatsUpAllReturnedCollateral();
        }
    }

    // --- Public functions ---

    function addCollateralToken(
        IERC20 collateralToken,
        IPriceFeed priceFeed,
        ISplitLiquidationCollateral newSplitLiquidationCollateral
    )
        public
        virtual
        override
    {
        addCollateralToken(
            collateralToken,
            priceFeed,
            newSplitLiquidationCollateral,
            new ERC20Indexable(
                address(this),
                string(bytes.concat("Raft ", bytes(IERC20Metadata(address(collateralToken)).name()), " collateral")),
                string(bytes.concat("r", bytes(IERC20Metadata(address(collateralToken)).symbol()), "-c")),
                type(uint256).max
            ),
            new ERC20Indexable(
                address(this),
                string(bytes.concat("Raft ", bytes(IERC20Metadata(address(collateralToken)).name()), " debt")),
                string(bytes.concat("r", bytes(IERC20Metadata(address(collateralToken)).symbol()), "-d")),
                type(uint256).max
            )
        );
    }

    function addCollateralToken(
        IERC20 collateralToken,
        IPriceFeed priceFeed,
        ISplitLiquidationCollateral newSplitLiquidationCollateral,
        IERC20Indexable raftCollateralToken_,
        IERC20Indexable raftDebtToken_
    )
        public
        override
        onlyOwner
    {
        if (address(collateralToken) == address(0)) {
            revert CollateralTokenAddressCannotBeZero();
        }
        if (address(priceFeed) == address(0)) {
            revert PriceFeedAddressCannotBeZero();
        }
        if (address(collateralInfo[collateralToken].collateralToken) != address(0)) {
            revert CollateralTokenAlreadyAdded();
        }

        CollateralTokenInfo memory raftCollateralTokenInfo;
        raftCollateralTokenInfo.collateralToken = raftCollateralToken_;
        raftCollateralTokenInfo.debtToken = raftDebtToken_;
        raftCollateralTokenInfo.isEnabled = true;
        raftCollateralTokenInfo.priceFeed = priceFeed;

        collateralInfo[collateralToken] = raftCollateralTokenInfo;

        setRedemptionSpread(collateralToken, MathUtils._100_PERCENT);
        setRedemptionRebate(collateralToken, MathUtils._100_PERCENT);

        setSplitLiquidationCollateral(collateralToken, newSplitLiquidationCollateral);

        emit CollateralTokenAdded(
            collateralToken, raftCollateralTokenInfo.collateralToken, raftCollateralTokenInfo.debtToken, priceFeed
        );
    }

    function setCollateralEnabled(
        IERC20 collateralToken,
        bool isEnabled
    )
        public
        override
        onlyOwner
        collateralTokenExists(collateralToken)
    {
        bool previousIsEnabled = collateralInfo[collateralToken].isEnabled;
        collateralInfo[collateralToken].isEnabled = isEnabled;

        if (previousIsEnabled != isEnabled) {
            emit CollateralTokenModified(collateralToken, isEnabled);
        }
    }

    function setSplitLiquidationCollateral(
        IERC20 collateralToken,
        ISplitLiquidationCollateral newSplitLiquidationCollateral
    )
        public
        override
        onlyOwner
    {
        if (address(newSplitLiquidationCollateral) == address(0)) {
            revert SplitLiquidationCollateralCannotBeZero();
        }
        collateralInfo[collateralToken].splitLiquidation = newSplitLiquidationCollateral;
        emit SplitLiquidationCollateralChanged(collateralToken, newSplitLiquidationCollateral);
    }

    function setRedemptionSpread(IERC20 collateralToken, uint256 newRedemptionSpread) public override onlyOwner {
        if (newRedemptionSpread > MathUtils._100_PERCENT) {
            revert RedemptionSpreadOutOfRange();
        }
        collateralInfo[collateralToken].redemptionSpread = newRedemptionSpread;
        emit RedemptionSpreadUpdated(collateralToken, newRedemptionSpread);
    }

    function getRedemptionRateWithDecay(IERC20 collateralToken) public view override returns (uint256) {
        return _calcRedemptionRate(collateralToken, _calcDecayedBaseRate(collateralToken));
    }

    function raftCollateralToken(IERC20 collateralToken) external view override returns (IERC20Indexable) {
        return collateralInfo[collateralToken].collateralToken;
    }

    function raftDebtToken(IERC20 collateralToken) external view override returns (IERC20Indexable) {
        return collateralInfo[collateralToken].debtToken;
    }

    function priceFeed(IERC20 collateralToken) external view override returns (IPriceFeed) {
        return collateralInfo[collateralToken].priceFeed;
    }

    function splitLiquidationCollateral(IERC20 collateralToken) external view returns (ISplitLiquidationCollateral) {
        return collateralInfo[collateralToken].splitLiquidation;
    }

    function collateralEnabled(IERC20 collateralToken) external view override returns (bool) {
        return collateralInfo[collateralToken].isEnabled;
    }

    function lastFeeOperationTime(IERC20 collateralToken) external view override returns (uint256) {
        return collateralInfo[collateralToken].lastFeeOperationTime;
    }

    function borrowingSpread(IERC20 collateralToken) external view override returns (uint256) {
        return collateralInfo[collateralToken].borrowingSpread;
    }

    function baseRate(IERC20 collateralToken) external view override returns (uint256) {
        return collateralInfo[collateralToken].baseRate;
    }

    function redemptionSpread(IERC20 collateralToken) external view override returns (uint256) {
        return collateralInfo[collateralToken].redemptionSpread;
    }

    function redemptionRebate(IERC20 collateralToken) external view override returns (uint256) {
        return collateralInfo[collateralToken].redemptionRebate;
    }

    function getRedemptionRate(IERC20 collateralToken) public view override returns (uint256) {
        return _calcRedemptionRate(collateralToken, collateralInfo[collateralToken].baseRate);
    }

    function getRedemptionFee(
        IERC20 collateralToken,
        uint256 collateralAmount,
        uint256 priceDeviation
    )
        public
        view
        override
        returns (uint256)
    {
        return Math.min(getRedemptionRate(collateralToken) + priceDeviation, MathUtils._100_PERCENT).mulDown(
            collateralAmount
        );
    }

    function getBorrowingRate(IERC20 collateralToken) public view override returns (uint256) {
        return _calcBorrowingRate(collateralToken, collateralInfo[collateralToken].baseRate);
    }

    function getBorrowingRateWithDecay(IERC20 collateralToken) public view override returns (uint256) {
        return _calcBorrowingRate(collateralToken, _calcDecayedBaseRate(collateralToken));
    }

    function getBorrowingFee(IERC20 collateralToken, uint256 debtAmount) public view override returns (uint256) {
        return getBorrowingRate(collateralToken).mulDown(debtAmount);
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
        IERC20 collateralToken,
        IERC20Indexable raftDebtToken,
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
            uint256 totalDebtChange =
                debtChange + _triggerBorrowingFee(collateralToken, position, debtChange, maxFeePercentage);
            raftDebtToken.mint(position, totalDebtChange);
            _mintRTokens(msg.sender, debtChange);
        } else {
            raftDebtToken.burn(position, debtChange);
            _burnRTokens(msg.sender, debtChange);
        }

        emit DebtChanged(position, collateralToken, debtChange, isDebtIncrease);
    }

    /// @dev Mints R tokens
    function _mintRTokens(address to, uint256 amount) internal virtual {
        rToken.mint(to, amount);
    }

    /// @dev Burns R tokens
    function _burnRTokens(address from, uint256 amount) internal virtual {
        rToken.burn(from, amount);
    }

    /// @dev Adjusts the collateral of a given borrower by burning or minting the corresponding amount of Raft
    /// collateral token and transferring the corresponding amount of collateral token.
    /// @param collateralToken The token the borrower used as collateral.
    /// @param position The address of the borrower.
    /// @param collateralChange The amount of collateral to add or remove. Must be positive.
    /// @param isCollateralIncrease True if the collateral is being increased, false otherwise.
    function _adjustCollateral(
        IERC20 collateralToken,
        IERC20Indexable raftCollateralToken,
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
            raftCollateralToken.mint(position, collateralChange);
            collateralToken.safeTransferFrom(msg.sender, address(this), collateralChange);
        } else {
            raftCollateralToken.burn(position, collateralChange);
            collateralToken.safeTransfer(msg.sender, collateralChange);
        }

        emit CollateralChanged(position, collateralToken, collateralChange, isCollateralIncrease);
    }

    /// @dev Updates debt and collateral indexes for a given collateral token.
    /// @param collateralToken The collateral token for which to update the indexes.
    /// @param raftCollateralToken The raft collateral indexable token.
    /// @param raftDebtToken The raft debt indexable token.
    /// @param totalDebtForCollateral Totam amount of debt backed by collateral token.
    function _updateDebtAndCollateralIndex(
        IERC20 collateralToken,
        IERC20Indexable raftCollateralToken,
        IERC20Indexable raftDebtToken,
        uint256 totalDebtForCollateral
    )
        internal
    {
        raftDebtToken.setIndex(totalDebtForCollateral);
        raftCollateralToken.setIndex(collateralToken.balanceOf(address(this)));
    }

    function _closePosition(
        IERC20Indexable raftCollateralToken,
        IERC20Indexable raftDebtToken,
        address position,
        bool burnTokens
    )
        internal
    {
        collateralTokenForPosition[position] = IERC20(address(0));

        if (burnTokens) {
            raftDebtToken.burn(position, type(uint256).max);
            raftCollateralToken.burn(position, type(uint256).max);
        }
        emit PositionClosed(position);
    }

    // --- Borrowing & redemption fee helper functions ---

    /// @dev Updates the base rate from a redemption operation. Impacts on the base rate:
    /// 1. decays the base rate based on time passed since last redemption or R borrowing operation,
    /// 2. increases the base rate based on the amount redeemed, as a proportion of total supply.
    function _updateBaseRateFromRedemption(
        IERC20 collateralToken,
        uint256 collateralDrawn,
        uint256 price,
        uint256 totalDebtSupply
    )
        internal
        returns (uint256)
    {
        uint256 decayedBaseRate = _calcDecayedBaseRate(collateralToken);

        /* Convert the drawn collateral back to R at face value rate (1 R:1 USD), in order to get
        * the fraction of total supply that was redeemed at face value. */
        uint256 redeemedFraction = collateralDrawn * price / totalDebtSupply;

        uint256 newBaseRate = decayedBaseRate + redeemedFraction / BETA;
        newBaseRate = Math.min(newBaseRate, MathUtils._100_PERCENT); // cap baseRate at a maximum of 100%
        assert(newBaseRate > 0); // Base rate is always non-zero after redemption

        // Update the baseRate state variable
        collateralInfo[collateralToken].baseRate = newBaseRate;
        emit BaseRateUpdated(collateralToken, newBaseRate);

        _updateLastFeeOpTime(collateralToken);

        return newBaseRate;
    }

    function _calcRedemptionRate(IERC20 collateralToken, uint256 baseRate_) internal view returns (uint256) {
        return baseRate_ + collateralInfo[collateralToken].redemptionSpread;
    }

    function _calcBorrowingRate(IERC20 collateralToken, uint256 baseRate_) internal view returns (uint256) {
        return Math.min(collateralInfo[collateralToken].borrowingSpread + baseRate_, MAX_BORROWING_RATE);
    }

    /// @dev Updates the base rate based on time elapsed since the last redemption or R borrowing operation.
    function _decayBaseRateFromBorrowing(IERC20 collateralToken) internal {
        uint256 decayedBaseRate = _calcDecayedBaseRate(collateralToken);
        assert(decayedBaseRate <= MathUtils._100_PERCENT); // The baseRate can decay to 0

        collateralInfo[collateralToken].baseRate = decayedBaseRate;
        emit BaseRateUpdated(collateralToken, decayedBaseRate);

        _updateLastFeeOpTime(collateralToken);
    }

    /// @dev Update the last fee operation time only if time passed >= decay interval. This prevents base rate
    /// griefing.
    function _updateLastFeeOpTime(IERC20 collateralToken) internal {
        uint256 timePassed = block.timestamp - collateralInfo[collateralToken].lastFeeOperationTime;

        if (timePassed >= 1 minutes) {
            collateralInfo[collateralToken].lastFeeOperationTime = block.timestamp;
            emit LastFeeOpTimeUpdated(collateralToken, block.timestamp);
        }
    }

    function _calcDecayedBaseRate(IERC20 collateralToken) internal view returns (uint256) {
        uint256 minutesPassed = (block.timestamp - collateralInfo[collateralToken].lastFeeOperationTime) / 1 minutes;
        uint256 decayFactor = MathUtils._decPow(MINUTE_DECAY_FACTOR, minutesPassed);

        return collateralInfo[collateralToken].baseRate.mulDown(decayFactor);
    }

    function _triggerBorrowingFee(
        IERC20 collateralToken,
        address position,
        uint256 debtAmount,
        uint256 maxFeePercentage
    )
        internal
        virtual
        returns (uint256 borrowingFee)
    {
        _decayBaseRateFromBorrowing(collateralToken); // decay the baseRate state variable
        borrowingFee = getBorrowingFee(collateralToken, debtAmount);

        _checkValidFee(borrowingFee, debtAmount, maxFeePercentage);

        if (borrowingFee > 0) {
            _mintRTokens(feeRecipient, borrowingFee);
            emit RBorrowingFeePaid(collateralToken, position, borrowingFee);
        }
    }

    // --- Validation check helper functions ---

    function _checkValidPosition(IERC20 collateralToken, uint256 positionDebt, uint256 positionCollateral) internal {
        ISplitLiquidationCollateral splitCollateral = collateralInfo[collateralToken].splitLiquidation;
        if (positionDebt < splitCollateral.LOW_TOTAL_DEBT()) {
            revert NetDebtBelowMinimum(positionDebt);
        }

        (uint256 price,) = collateralInfo[collateralToken].priceFeed.fetchPrice();
        uint256 newICR = MathUtils._computeCR(positionCollateral, positionDebt, price);
        if (newICR < splitCollateral.MCR()) {
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
