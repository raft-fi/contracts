// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// import "../PositionManager.sol";
// import "../BorrowerOperations.sol";
// import "../StabilityPool.sol";
// import "../RToken.sol";

// contract EchidnaProxy {
//     PositionManager positionManager;
//     BorrowerOperations borrowerOperations;
//     StabilityPool stabilityPool;
//     RToken rToken;

//     constructor(
//         PositionManager _positionManager,
//         BorrowerOperations _borrowerOperations,
//         StabilityPool _stabilityPool,
//         RToken _rToken
//     ) public {
//         positionManager = _positionManager;
//         borrowerOperations = _borrowerOperations;
//         stabilityPool = _stabilityPool;
//         rToken = _rToken;
//     }

//     // PositionManager

//     function liquidatePrx(address _user) external {
//         positionManager.liquidate(_user);
//     }

//     function liquidatePositionsPrx(uint _n) external {
//         positionManager.liquidatePositions(_n);
//     }

//     function batchLiquidatePositionsPrx(address[] calldata _positionArray) external {
//         positionManager.batchLiquidatePositions(_positionArray);
//     }

//     function redeemCollateralPrx(
//         uint _debtAmount,
//         address _firstRedemptionHint,
//         address _upperPartialRedemptionHint,
//         address _lowerPartialRedemptionHint,
//         uint _partialRedemptionHintNICR,
//         uint _maxIterations,
//         uint _maxFee
//     ) external {
//         positionManager.redeemCollateral(_debtAmount, _firstRedemptionHint, _upperPartialRedemptionHint,
//             _lowerPartialRedemptionHint, _partialRedemptionHintNICR, _maxIterations, _maxFee);
//     }

//     // Borrower Operations
//    function openPositionPrx(
//        uint _ETH,
//        uint _debtAmount,
//        address _upperHint,
//        address _lowerHint,
//        uint _maxFee
//    ) external {
//        borrowerOperations.openPosition(_maxFee, _debtAmount, _upperHint, _lowerHint, _ETH);
//    }

//     function addCollPrx(uint _ETH, address _upperHint, address _lowerHint) external {
//         borrowerOperations.addColl(_upperHint, _lowerHint, _ETH);
//     }

//     function withdrawCollPrx(uint _amount, address _upperHint, address _lowerHint) external {
//         borrowerOperations.withdrawColl(_amount, _upperHint, _lowerHint);
//     }

//     function withdrawDebtPrx(uint _amount, address _upperHint, address _lowerHint, uint _maxFee) external {
//         borrowerOperations.withdrawDebt(_maxFee, _amount, _upperHint, _lowerHint);
//     }

//     function repayRPrx(uint _amount, address _upperHint, address _lowerHint) external {
//         borrowerOperations.repayDebt(_amount, _upperHint, _lowerHint);
//     }

//     function closePositionPrx() external {
//         borrowerOperations.closePosition();
//     }

//     function adjustPositionPrx(uint _ETH, uint _collWithdrawal, uint _debtChange, bool _isDebtIncrease,
//         address _upperHint, address _lowerHint, uint _maxFee) external {
//         borrowerOperations.adjustPosition(_maxFee, _collWithdrawal, _debtChange, _isDebtIncrease, _upperHint,
// _lowerHint, _ETH);
//     }

//     // Pool Manager
//     function provideToSPPrx(uint _amount) external {
//         stabilityPool.provideToSP(_amount);
//     }

//     function withdrawFromSPPrx(uint _amount) external {
//         stabilityPool.withdrawFromSP(_amount);
//     }

//     // R Token

//     function transferPrx(address recipient, uint256 amount) external returns (bool) {
//         return rToken.transfer(recipient, amount);
//     }

//     function approvePrx(address spender, uint256 amount) external returns (bool) {
//         return rToken.approve(spender, amount);
//     }

//     function transferFromPrx(address sender, address recipient, uint256 amount) external returns (bool) {
//         return rToken.transferFrom(sender, recipient, amount);
//     }

//     function increaseAllowancePrx(address spender, uint256 addedValue) external returns (bool) {
//         return rToken.increaseAllowance(spender, addedValue);
//     }

//     function decreaseAllowancePrx(address spender, uint256 subtractedValue) external returns (bool) {
//         return rToken.decreaseAllowance(spender, subtractedValue);
//     }
// }
