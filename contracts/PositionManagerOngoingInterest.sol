// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { MathUtils } from "./Dependencies/MathUtils.sol";
import { ILock } from "./Interfaces/ILock.sol";
import { IERC20Wrapped } from "./Interfaces/IERC20Wrapped.sol";
import { IPositionManager } from "./Interfaces/IPositionManager.sol";
import { IPriceFeed } from "./Interfaces/IPriceFeed.sol";
import { PositionManagerWrappedCollateralToken } from "./PositionManagerWrappedCollateralToken.sol";
import { PositionManagerDependent } from "./PositionManagerDependent.sol";

/// TODO: IMPORTANT have this per collateral token or a global one? make it global probably
contract PositionManagerOngoingInterest is Ownable2Step, PositionManagerWrappedCollateralToken {
    using Fixed256x18 for uint256;

    uint256 public constant INTEREST_RATE_PRECISION = 1e18;

    IERC20 public immutable debtToken;
    IERC20 public immutable raftCollateralToken;
    IPriceFeed public immutable priceFeed;

    uint256 public interestRatePerSecond;
    mapping(address => uint256) public pendingInterestStored;
    mapping(address => uint256) public lastPendingInterestUpdate;

    event Recovered(address indexed token, uint256 amount);
    event InterestPaid(address indexed position, uint256 interestPaid, uint256 pendingInterest);

    /// TODO: IMPORTANT leave like dis or use callback instead?
    modifier unlockCollateralToken() {
        ILock(address(wrappedCollateralToken)).unlock();
        _;
        ILock(address(wrappedCollateralToken)).lock();
    }

    constructor(
        address positionManager_,
        IERC20Wrapped wrappedCollateralToken_,
        uint256 interestRatePerSecond_
    )
        PositionManagerWrappedCollateralToken(positionManager_, wrappedCollateralToken_)
    {
        (, debtToken, priceFeed,,,,,,,) = IPositionManager(positionManager).collateralInfo(wrappedCollateralToken_);
        raftCollateralToken = IPositionManager(positionManager).raftCollateralToken(wrappedCollateralToken_);
        interestRatePerSecond = interestRatePerSecond_;
    }

    function pendingInterest(address position) public view returns (uint256) {
        uint256 debtBalance = debtToken.balanceOf(position);
        if (debtBalance == 0) return 0;

        uint256 timeElapsed = block.timestamp - lastPendingInterestUpdate[msg.sender];
        uint256 pendingInterestSinceUpdate =
            debtBalance * (interestRatePerSecond * timeElapsed) / INTEREST_RATE_PRECISION;

        return pendingInterestSinceUpdate + pendingInterestStored[msg.sender];
    }

    function setInterestRate(uint256 interestRatePerSecond_) external onlyOwner {
        interestRatePerSecond = interestRatePerSecond_;
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        if (tokenAddress == address(wrappedCollateralToken)) {
            wrappedCollateralToken.withdrawTo(msg.sender, tokenAmount);
        } else {
            IERC20(tokenAddress).transfer(msg.sender, tokenAmount);
        }

        emit Recovered(tokenAddress, tokenAmount);
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
        unlockCollateralToken
    {
        _payInterest();
        super.managePosition(
            collateralChange, isCollateralIncrease, debtChange, isDebtIncrease, maxFeePercentage, permitSignature
        );
    }

    error NotSupported();

    function redeemCollateral(uint256, uint256, ERC20PermitSignature calldata) public override {
        /// TODO: IMPORTANT wut do? revert NotSupported()? or add support
        revert NotSupported();
    }

    /// TODO: IMPORTANT create interface and add dis?
    function liquidate(address position) external unlockCollateralToken {
        uint256 positionDebt = debtToken.balanceOf(position);

        _rToken.transferFrom(msg.sender, address(this), positionDebt);

        uint256 balBefore = wrappedCollateralToken.balanceOf(address(this));
        IPositionManager(positionManager).liquidate(position);
        uint256 liquidatorReward = wrappedCollateralToken.balanceOf(address(this)) - balBefore;
        wrappedCollateralToken.withdrawTo(msg.sender, liquidatorReward);

        /// TODO: IMPORTANT discuss
        pendingInterestStored[position] = 0;
        lastPendingInterestUpdate[position] = block.timestamp;
    }

    function _payInterest() internal {
        uint256 pendingInterest_ = pendingInterest(msg.sender);
        lastPendingInterestUpdate[msg.sender] = block.timestamp;
        if (pendingInterest_ == 0) return;

        uint256 maxMintableDebt = _getMaxMintableDebt(msg.sender);
        uint256 debtToMint;
        uint256 appliedBorrowingFee;
        if (pendingInterest_ > maxMintableDebt) {
            (debtToMint, appliedBorrowingFee) = _applyBorrowingFee(maxMintableDebt);
            pendingInterestStored[msg.sender] = pendingInterest_ - maxMintableDebt;
        } else {
            (debtToMint, appliedBorrowingFee) = _applyBorrowingFee(pendingInterest_);
            pendingInterestStored[msg.sender] = 0;
        }

        ERC20PermitSignature memory emptySignature;
        (, uint256 actualDebtChange) = IPositionManager(positionManager).managePosition(
            wrappedCollateralToken, msg.sender, 0, false, debtToMint, true, appliedBorrowingFee, emptySignature
        );

        emit InterestPaid(msg.sender, actualDebtChange, pendingInterestStored[msg.sender]);
    }

    // IPositionManager(positionManager).splitLiquidationCollateral(wrappedCollateralToken).MCR()
    function _getMaxMintableDebt(address position) internal returns (uint256) {
        (uint256 price,) = priceFeed.fetchPrice();
        uint256 collateralBalance = raftCollateralToken.balanceOf(position);
        uint256 debtBalance = debtToken.balanceOf(position);
        uint256 MCR = IPositionManager(positionManager).splitLiquidationCollateral(wrappedCollateralToken).MCR();

        uint256 maxDebt = collateralBalance * price / MCR;
        return debtBalance >= maxDebt ? 0 : maxDebt - debtBalance;
    }

    function _applyBorrowingFee(uint256 amount)
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
