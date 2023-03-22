// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
    string constant public NAME = "BorrowerWrappersScript";

    ITroveManager immutable troveManager;
    IStabilityPool immutable stabilityPool;
    IPriceFeed immutable priceFeed;
    IERC20 immutable lusdToken;
    IERC20 immutable lqtyToken;
    IERC20 immutable collateralToken;
    ILQTYStaking immutable lqtyStaking;

    constructor(
        address _borrowerOperationsAddress,
        address _troveManagerAddress,
        address _lqtyStakingAddress
    )
        BorrowerOperationsScript(IBorrowerOperations(_borrowerOperationsAddress))
        LQTYStakingScript(_lqtyStakingAddress)
        public
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

        address collateralTokenCached = stabilityPoolCached.collateralToken();
        checkContract(collateralTokenCached);
        collateralToken = IERC20(collateralTokenCached);

        ILQTYStaking lqtyStakingCached = troveManagerCached.lqtyStaking();
        require(_lqtyStakingAddress == address(lqtyStakingCached), "BorrowerWrappersScript: Wrong LQTYStaking address");
        lqtyStaking = lqtyStakingCached;
    }

    function claimCollateralAndOpenTrove(uint _maxFee, uint _LUSDAmount, address _upperHint, address _lowerHint, uint _amount) external {
        uint balanceBefore = collateralToken.balanceOf(address(this));

        // Claim collateral
        borrowerOperations.claimCollateral();

        uint balanceAfter = collateralToken.balanceOf(address(this));

        // already checked in CollSurplusPool
        assert(balanceAfter > balanceBefore);

        uint totalCollateral = balanceAfter - balanceBefore + _amount;

        // Open trove with obtained collateral, plus collateral sent by user
        borrowerOperations.openTrove(_maxFee, _LUSDAmount, _upperHint, _lowerHint, totalCollateral);
    }

    function claimSPRewardsAndRecycle(uint _maxFee, address _upperHint, address _lowerHint) external {
        uint collBalanceBefore = collateralToken.balanceOf(address(this));
        uint lqtyBalanceBefore = lqtyToken.balanceOf(address(this));

        // Claim rewards
        stabilityPool.withdrawFromSP(0);

        uint collBalanceAfter = collateralToken.balanceOf(address(this));
        uint lqtyBalanceAfter = lqtyToken.balanceOf(address(this));
        uint claimedCollateral = collBalanceAfter - collBalanceBefore;

        // Add claimed ETH to trove, get more LUSD and stake it into the Stability Pool
        if (claimedCollateral > 0) {
            _requireUserHasTrove(address(this));
            uint LUSDAmount = _getNetLUSDAmount(claimedCollateral);
            borrowerOperations.adjustTrove(_maxFee, 0, LUSDAmount, true, _upperHint, _lowerHint, claimedCollateral);
            // Provide withdrawn LUSD to Stability Pool
            if (LUSDAmount > 0) {
                stabilityPool.provideToSP(LUSDAmount);
            }
        }

        // Stake claimed LQTY
        uint claimedLQTY = lqtyBalanceAfter - lqtyBalanceBefore;
        if (claimedLQTY > 0) {
            lqtyStaking.stake(claimedLQTY);
        }
    }

    function claimStakingGainsAndRecycle(uint _maxFee, address _upperHint, address _lowerHint) external {
        uint collBalanceBefore = collateralToken.balanceOf(address(this));
        uint lusdBalanceBefore = lusdToken.balanceOf(address(this));
        uint lqtyBalanceBefore = lqtyToken.balanceOf(address(this));

        // Claim gains
        lqtyStaking.unstake(0);

        uint gainedCollateral = collateralToken.balanceOf(address(this)) - collBalanceBefore; // stack too deep issues :'(
        uint gainedLUSD = lusdToken.balanceOf(address(this)) - lusdBalanceBefore;

        uint netLUSDAmount;
        // Top up trove and get more LUSD, keeping ICR constant
        if (gainedCollateral > 0) {
            _requireUserHasTrove(address(this));
            netLUSDAmount = _getNetLUSDAmount(gainedCollateral);
            borrowerOperations.adjustTrove(_maxFee, 0, netLUSDAmount, true, _upperHint, _lowerHint, gainedCollateral);
        }

        uint totalLUSD = gainedLUSD + netLUSDAmount;
        if (totalLUSD > 0) {
            stabilityPool.provideToSP(totalLUSD);

            // Providing to Stability Pool also triggers LQTY claim, so stake it if any
            uint lqtyBalanceAfter = lqtyToken.balanceOf(address(this));
            uint claimedLQTY = lqtyBalanceAfter - lqtyBalanceBefore;
            if (claimedLQTY > 0) {
                lqtyStaking.stake(claimedLQTY);
            }
        }

    }

    function _getNetLUSDAmount(uint _collateral) internal returns (uint) {
        uint price = priceFeed.fetchPrice();
        uint ICR = troveManager.getCurrentICR(address(this), price);

        uint LUSDAmount = _collateral * price / ICR;
        uint borrowingRate = troveManager.getBorrowingRateWithDecay();
        uint netDebt = LUSDAmount * LiquityMath.DECIMAL_PRECISION / (LiquityMath.DECIMAL_PRECISION + borrowingRate);

        return netDebt;
    }

    function _requireUserHasTrove(address _depositor) internal view {
        require(troveManager.getTroveStatus(_depositor) == 1, "BorrowerWrappersScript: caller must have an active trove");
    }
}
