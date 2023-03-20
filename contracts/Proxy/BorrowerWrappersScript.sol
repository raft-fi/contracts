// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../Dependencies/LiquityMath.sol";
import "../Interfaces/IBorrowerOperations.sol";
import "../Interfaces/ITroveManager.sol";
import "../Interfaces/IStabilityPool.sol";
import "../Interfaces/IPriceFeed.sol";
import "../Interfaces/ILQTYStaking.sol";
import "./BorrowerOperationsScript.sol";
import "./ETHTransferScript.sol";
import "./LQTYStakingScript.sol";

contract BorrowerWrappersScript is BorrowerOperationsScript, ETHTransferScript, LQTYStakingScript {
    string public constant NAME = "BorrowerWrappersScript";

    ITroveManager immutable troveManager;
    IStabilityPool immutable stabilityPool;
    IPriceFeed immutable priceFeed;
    IERC20 immutable lusdToken;
    IERC20 immutable lqtyToken;
    ILQTYStaking immutable lqtyStaking;

    constructor(address _borrowerOperationsAddress, address _troveManagerAddress, address _lqtyStakingAddress)
        public
        BorrowerOperationsScript(IBorrowerOperations(_borrowerOperationsAddress))
        LQTYStakingScript(_lqtyStakingAddress)
    {
        checkContract(_troveManagerAddress);
        ITroveManager troveManagerCached = ITroveManager(_troveManagerAddress);
        troveManager = troveManagerCached;

        IStabilityPool stabilityPoolCached = troveManagerCached.stabilityPool();
        checkContract(address(stabilityPoolCached));
        stabilityPool = stabilityPoolCached;

        IPriceFeed priceFeedCached = troveManagerCached.priceFeed();
        checkContract(address(priceFeedCached));
        priceFeed = priceFeedCached;

        address lusdTokenCached = address(troveManagerCached.lusdToken());
        checkContract(lusdTokenCached);
        lusdToken = IERC20(lusdTokenCached);

        address lqtyTokenCached = address(troveManagerCached.lqtyToken());
        checkContract(lqtyTokenCached);
        lqtyToken = IERC20(lqtyTokenCached);

        ILQTYStaking lqtyStakingCached = troveManagerCached.lqtyStaking();
        require(_lqtyStakingAddress == address(lqtyStakingCached), "BorrowerWrappersScript: Wrong LQTYStaking address");
        lqtyStaking = lqtyStakingCached;
    }

    function claimCollateralAndOpenTrove(uint256 _maxFee, uint256 _LUSDAmount, address _upperHint, address _lowerHint)
        external
        payable
    {
        uint256 balanceBefore = address(this).balance;

        // Claim collateral
        borrowerOperations.claimCollateral();

        uint256 balanceAfter = address(this).balance;

        // already checked in CollSurplusPool
        assert(balanceAfter > balanceBefore);

        uint256 totalCollateral = balanceAfter - balanceBefore + msg.value;

        // Open trove with obtained collateral, plus collateral sent by user
        borrowerOperations.openTrove{value: totalCollateral}(_maxFee, _LUSDAmount, _upperHint, _lowerHint);
    }

    function claimSPRewardsAndRecycle(uint256 _maxFee, address _upperHint, address _lowerHint) external {
        uint256 collBalanceBefore = address(this).balance;
        uint256 lqtyBalanceBefore = lqtyToken.balanceOf(address(this));

        // Claim rewards
        stabilityPool.withdrawFromSP(0);

        uint256 collBalanceAfter = address(this).balance;
        uint256 lqtyBalanceAfter = lqtyToken.balanceOf(address(this));
        uint256 claimedCollateral = collBalanceAfter - collBalanceBefore;

        // Add claimed ETH to trove, get more LUSD and stake it into the Stability Pool
        if (claimedCollateral > 0) {
            _requireUserHasTrove(address(this));
            uint256 LUSDAmount = _getNetLUSDAmount(claimedCollateral);
            borrowerOperations.adjustTrove{value: claimedCollateral}(
                _maxFee, 0, LUSDAmount, true, _upperHint, _lowerHint
            );
            // Provide withdrawn LUSD to Stability Pool
            if (LUSDAmount > 0) {
                stabilityPool.provideToSP(LUSDAmount, address(0));
            }
        }

        // Stake claimed LQTY
        uint256 claimedLQTY = lqtyBalanceAfter - lqtyBalanceBefore;
        if (claimedLQTY > 0) {
            lqtyStaking.stake(claimedLQTY);
        }
    }

    function claimStakingGainsAndRecycle(uint256 _maxFee, address _upperHint, address _lowerHint) external {
        uint256 collBalanceBefore = address(this).balance;
        uint256 lusdBalanceBefore = lusdToken.balanceOf(address(this));
        uint256 lqtyBalanceBefore = lqtyToken.balanceOf(address(this));

        // Claim gains
        lqtyStaking.unstake(0);

        uint256 gainedCollateral = address(this).balance - collBalanceBefore;
        uint256 gainedLUSD = lusdToken.balanceOf(address(this)) - lusdBalanceBefore;

        uint256 netLUSDAmount;
        // Top up trove and get more LUSD, keeping ICR constant
        if (gainedCollateral > 0) {
            _requireUserHasTrove(address(this));
            netLUSDAmount = _getNetLUSDAmount(gainedCollateral);
            borrowerOperations.adjustTrove{value: gainedCollateral}(
                _maxFee, 0, netLUSDAmount, true, _upperHint, _lowerHint
            );
        }

        uint256 totalLUSD = gainedLUSD + netLUSDAmount;
        if (totalLUSD > 0) {
            stabilityPool.provideToSP(totalLUSD, address(0));

            // Providing to Stability Pool also triggers LQTY claim, so stake it if any
            uint256 lqtyBalanceAfter = lqtyToken.balanceOf(address(this));
            uint256 claimedLQTY = lqtyBalanceAfter - lqtyBalanceBefore;
            if (claimedLQTY > 0) {
                lqtyStaking.stake(claimedLQTY);
            }
        }
    }

    function _getNetLUSDAmount(uint256 _collateral) internal returns (uint256) {
        uint256 price = priceFeed.fetchPrice();
        uint256 ICR = troveManager.getCurrentICR(address(this), price);

        uint256 LUSDAmount = _collateral * price / ICR;
        uint256 borrowingRate = troveManager.getBorrowingRateWithDecay();
        uint256 netDebt = LUSDAmount * LiquityMath.DECIMAL_PRECISION / (LiquityMath.DECIMAL_PRECISION + borrowingRate);

        return netDebt;
    }

    function _requireUserHasTrove(address _depositor) internal view {
        require(
            troveManager.getTroveStatus(_depositor) == 1, "BorrowerWrappersScript: caller must have an active trove"
        );
    }
}
