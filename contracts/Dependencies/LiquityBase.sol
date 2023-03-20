// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./BaseMath.sol";
import "./LiquityMath.sol";
import "../Interfaces/IActivePool.sol";
import "../Interfaces/IDefaultPool.sol";
import "../Interfaces/IPriceFeed.sol";
import "../Interfaces/ILiquityBase.sol";

/*
* Base contract for TroveManager, BorrowerOperations and StabilityPool. Contains global system constants and
* common functions.
*/
contract LiquityBase is BaseMath, ILiquityBase {
    uint256 public constant _100pct = 1000000000000000000; // 1e18 == 100%

    // Minimum collateral ratio for individual troves
    uint256 public constant MCR = 1100000000000000000; // 110%

    // Amount of LUSD to be locked in gas pool on opening troves
    uint256 public constant LUSD_GAS_COMPENSATION = 200e18;

    // Minimum amount of net LUSD debt a trove must have
    uint256 public constant MIN_NET_DEBT = 1800e18;
    // uint constant public MIN_NET_DEBT = 0;

    uint256 public constant PERCENT_DIVISOR = 200; // dividing by 200 yields 0.5%

    uint256 public constant BORROWING_FEE_FLOOR = DECIMAL_PRECISION / 1000 * 5; // 0.5%

    IActivePool public activePool;

    IDefaultPool public defaultPool;

    IPriceFeed public override priceFeed;

    // --- Gas compensation functions ---

    // Returns the composite debt (drawn debt + gas compensation) of a trove, for the purpose of ICR calculation
    function _getCompositeDebt(uint256 _debt) internal pure returns (uint256) {
        return _debt + LUSD_GAS_COMPENSATION;
    }

    function _getNetDebt(uint256 _debt) internal pure returns (uint256) {
        return _debt - LUSD_GAS_COMPENSATION;
    }

    // Return the amount of ETH to be drawn from a trove's collateral and sent as gas compensation.
    function _getCollGasCompensation(uint256 _entireColl) internal pure returns (uint256) {
        return _entireColl / PERCENT_DIVISOR;
    }

    function getEntireSystemColl() public view returns (uint256 entireSystemColl) {
        uint256 activeColl = activePool.getETH();
        uint256 liquidatedColl = defaultPool.getETH();

        return activeColl + liquidatedColl;
    }

    function getEntireSystemDebt() public view returns (uint256 entireSystemDebt) {
        uint256 activeDebt = activePool.getLUSDDebt();
        uint256 closedDebt = defaultPool.getLUSDDebt();

        return activeDebt + closedDebt;
    }

    function _getTCR(uint256 _price) internal view returns (uint256 TCR) {
        uint256 entireSystemColl = getEntireSystemColl();
        uint256 entireSystemDebt = getEntireSystemDebt();

        TCR = LiquityMath._computeCR(entireSystemColl, entireSystemDebt, _price);

        return TCR;
    }

    function _requireUserAcceptsFee(uint256 _fee, uint256 _amount, uint256 _maxFeePercentage) internal pure {
        uint256 feePercentage = _fee * DECIMAL_PRECISION / _amount;
        require(feePercentage <= _maxFeePercentage, "Fee exceeded provided maximum");
    }
}
