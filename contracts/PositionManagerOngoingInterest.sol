// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { MathUtils } from "./Dependencies/MathUtils.sol";
import { IERC20WrappedLockable } from "./Interfaces/IERC20WrappedLockable.sol";
import { IPositionManager } from "./Interfaces/IPositionManager.sol";
import { IPriceFeed } from "./Interfaces/IPriceFeed.sol";
import { PositionManagerWrappedCollateralToken } from "./PositionManagerWrappedCollateralToken.sol";
import { PositionManagerDependent } from "./PositionManagerDependent.sol";

/// TODO: IMPORTANT have this per collateral token or a global one? make it global probably
contract PositionManagerOngoingInterest is Ownable2Step, PositionManagerWrappedCollateralToken {
    using Fixed256x18 for uint256;

    uint256 public constant INTEREST_RATE_PRECISION = 1e18;

    IERC20 public immutable debtToken;
    IPriceFeed public immutable priceFeed;

    uint256 public interestRatePerSecond;
    mapping(address => uint256) public pendingInterestStored;
    mapping(address => uint256) public lastPendingInterestUpdate;
    /// TODO: IMPORTANT probably add another mapping that maps pending rewards that were unpaid on the
    /// lastPendingInterestUpdate update
    /// (btw maybe rename it to lastInterestPaymentUpdate becuz of that) due to reaching the maximum
    /// collateralization ratio, so that they can be paid later if CR increases

    /// TODO: IMPORTANT leave like dis or use callback instead?
    // modifier unlockCollateralToken {
    //     wrappedCollateralToken.unlock();
    //     _;
    //     wrappedCollateralToken.lock();
    // }

    constructor(
        address positionManager_,
        IERC20WrappedLockable wrappedCollateralToken_,
        uint256 interestRatePerSecond_
    )
        PositionManagerWrappedCollateralToken(positionManager_, wrappedCollateralToken_)
    {
        (, debtToken, priceFeed,,,,,,,) = IPositionManager(positionManager).collateralInfo(wrappedCollateralToken_);
        interestRatePerSecond = interestRatePerSecond_;
    }

    function setInterestRate(uint256 interestRatePerSecond_) external onlyOwner {
        interestRatePerSecond = interestRatePerSecond_;
    }

    function managePosition(
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        ERC20PermitSignature calldata permitSignature
    )
        public
        override
    {
        _payInterest();
        // tODO: IMPORTANT add feeRecipient to send R to, or just add recoverERC20 which owner can call.
        /// TODO: IMPORTANT emit event
        /// }
        super.managePosition(
            collateralChange, isCollateralIncrease, debtChange, isDebtIncrease, maxFeePercentage, permitSignature
        );
    }

    function _payInterest() internal {
        uint256 pendingInterest_ = pendingInterest(msg.sender);
        if (pendingInterest_ == 0) return;

        uint256 maxMintableDebt = getMaxMintableDebt(msg.sender);

        uint256 debtToMint;
        uint256 appliedBorrowingFee;
        if (pendingInterest_ > maxMintableDebt) {
            (debtToMint, appliedBorrowingFee) = applyBorrowingFee(maxMintableDebt);
            pendingInterestStored[msg.sender] -= maxMintableDebt;
            /// TODO: IMPORTANT should deduct borrowing fee
        } else {
            (debtToMint, appliedBorrowingFee) = applyBorrowingFee(pendingInterest_);
            pendingInterestStored[msg.sender] = 0;
        }
        lastPendingInterestUpdate[msg.sender] = block.timestamp;

        ERC20PermitSignature memory emptySignature;
        IPositionManager(positionManager).managePosition(
            wrappedCollateralToken, msg.sender, 0, false, debtToMint, true, appliedBorrowingFee, emptySignature
        );
    }

    function redeemCollateral(
        uint256 debtAmount,
        uint256 maxFeePercentage,
        ERC20PermitSignature calldata permitSignature
    )
        public
        override
    {
        /// TODO: IMPORTANT wut do? revert NotSupported()? or add support
        require(false, "no");
    }

    /// TODO: IMPORTANT implement. create interface and add dis?
    function liquidate(address position) external { }

    /// TODO: IMPORTANT maybe this should return (uint256, uint256), which is the split that will be minted and cached
    function pendingInterest(address position) public view returns (uint256) {
        uint256 debtBalance = debtToken.balanceOf(position);
        if (debtBalance == 0) return 0;

        uint256 timeElapsed = block.timestamp - lastPendingInterestUpdate[msg.sender];
        /// TODO: IMPORTANT what if lastPendingInterestUpdate[msg.sender] is 0? this will happen on initial debt mint.
        /// Also think about end to end flows

        uint256 pendingInterestSinceUpdate =
            debtBalance * (interestRatePerSecond * timeElapsed) / INTEREST_RATE_PRECISION;
        return pendingInterestSinceUpdate + pendingInterestStored[msg.sender];
    }

    // IPositionManager(positionManager).splitLiquidationCollateral(wrappedCollateralToken).MCR()
    function getMaxMintableDebt(address position) internal returns (uint256) {
        (uint256 price,) = priceFeed.fetchPrice();
        uint256 collateralBalance = wrappedCollateralToken.balanceOf(position);
        uint256 debtBalance = debtToken.balanceOf(position);
        uint256 MCR = IPositionManager(positionManager).splitLiquidationCollateral(wrappedCollateralToken).MCR();

        uint256 maxDebt = collateralBalance * price / MCR;
        return debtBalance >= maxDebt ? 0 : maxDebt - debtBalance;
    }

    function applyBorrowingFee(uint256 amount)
        internal
        view
        returns (uint256 feeAdjustedAmount, uint256 appliedBorrowingFee)
    {
        uint256 borrowingFee = IPositionManager(positionManager).getBorrowingRateWithDecay(wrappedCollateralToken);
        return (amount.divDown(MathUtils._100_PERCENT + borrowingFee), borrowingFee);
    }

    /// Open questions
    /// TODO: IMPORTANT should debt be compounded? if yes, should we expose a public function to compound
    /// a position's debt? This would be useful if a position gets close to liquidation point and we want to compound
    /// its debt
    /// before liquidation (otherwise if there was no activity in the posiiton for a long time, it would be liquidated
    /// without paying interest)
    /// on the other hand, allowing anyone's debt to be compounded can be a unfavorable for borrowers maybe?
    /// this could be solved if we implement non compounding debt
}
