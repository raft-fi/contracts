// // SPDX-License-Identifier: MIT

// pragma solidity 0.8.19;

// import "../TroveManager.sol";
// import "../BorrowerOperations.sol";
// import "../ActivePool.sol";
// import "../DefaultPool.sol";
// import "../StabilityPool.sol";
// import "../RToken.sol";
// import "./PriceFeedTestnet.sol";
// import "../SortedTroves.sol";
// import "./EchidnaProxy.sol";
// import { WstETHTokenMock } from "./WstETHTokenMock.sol";

// // Run with:
// // rm -f fuzzTests/corpus/* # (optional)
// // ~/.local/bin/echidna-test contracts/TestContracts/EchidnaTester.sol --contract EchidnaTester --config fuzzTests/echidna_config.yaml

// contract EchidnaTester {
//     uint constant private NUMBER_OF_ACTORS = 100;
//     uint constant private INITIAL_BALANCE = 1e24;
//     uint private MCR;
//     uint constant private CCR = 1500000000000000000; // 150% TODO: delete when doing https://github.com/tempusfinance/raft/issues/17
//     uint private R_GAS_COMPENSATION;

//     TroveManager public troveManager;
//     BorrowerOperations public borrowerOperations;
//     ActivePool public activePool;
//     DefaultPool public defaultPool;
//     StabilityPool public stabilityPool;
//     RToken public rToken;
//     WstETHTokenMock public collateralToken;
//     PriceFeedTestnet priceFeedTestnet;
//     SortedTroves sortedTroves;

//     EchidnaProxy[NUMBER_OF_ACTORS] public echidnaProxies;

//     uint private numberOfTroves;

//     constructor() public {
//         troveManager = new TroveManager();
//         borrowerOperations = new BorrowerOperations();
//         collateralToken = new WstETHTokenMock();
//         activePool = new ActivePool(address(collateralToken));
//         defaultPool = new DefaultPool(address(collateralToken));
//         stabilityPool = new StabilityPool(address(collateralToken));
//         rToken = new RToken(
//             address(troveManager),
//             address(stabilityPool),
//             address(borrowerOperations)
//         );

//         priceFeedTestnet = new PriceFeedTestnet();

//         sortedTroves = new SortedTroves();

//         troveManager.setAddresses(address(borrowerOperations),
//             address(activePool), address(defaultPool),
//             address(stabilityPool),
//             address(priceFeedTestnet), address(rToken),
//             address(sortedTroves), address(0), address(0));

//         borrowerOperations.setAddresses(address(troveManager),
//             address(activePool), address(defaultPool),
//             address(stabilityPool),
//             address(priceFeedTestnet), address(sortedTroves),
//             address(rToken), address(0));

//         activePool.setAddresses(address(borrowerOperations),
//             address(troveManager), address(stabilityPool), address(defaultPool));

//         defaultPool.setAddresses(address(troveManager));

//         stabilityPool.setAddresses(address(borrowerOperations),
//             address(troveManager), address(activePool), address(rToken),
//             address(sortedTroves), address(priceFeedTestnet), address(0));

//         sortedTroves.setParams(1e18, address(troveManager), address(borrowerOperations));

//         for (uint i = 0; i < NUMBER_OF_ACTORS; i++) {
//             echidnaProxies[i] = new EchidnaProxy(troveManager, borrowerOperations, stabilityPool, rToken);
//             (bool success, ) = address(echidnaProxies[i]).call{value: INITIAL_BALANCE}("");
//             require(success);
//         }

//         MCR = borrowerOperations.MCR();
//         R_GAS_COMPENSATION = borrowerOperations.R_GAS_COMPENSATION();
//         require(MCR > 0);

//         // TODO:
//         priceFeedTestnet.setPrice(1e22);
//     }

//     // TroveManager

//     function liquidateExt(uint _i, address _user) external {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].liquidatePrx(_user);
//     }

//     function liquidateTrovesExt(uint _i, uint _n) external {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].liquidateTrovesPrx(_n);
//     }

//     function batchLiquidateTrovesExt(uint _i, address[] calldata _troveArray) external {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].batchLiquidateTrovesPrx(_troveArray);
//     }

//     function redeemCollateralExt(
//         uint _i,
//         uint _rAmount,
//         address _firstRedemptionHint,
//         address _upperPartialRedemptionHint,
//         address _lowerPartialRedemptionHint,
//         uint _partialRedemptionHintNICR
//     ) external {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].redeemCollateralPrx(_rAmount, _firstRedemptionHint, _upperPartialRedemptionHint, _lowerPartialRedemptionHint, _partialRedemptionHintNICR, 0, 0);
//     }

//     // Borrower Operations

//     function getAdjustedETH(uint actorBalance, uint _ETH, uint ratio) internal view returns (uint) {
//         uint price = priceFeedTestnet.getPrice();
//         require(price > 0);
//         uint minETH = ratio * R_GAS_COMPENSATION / price;
//         require(actorBalance > minETH);
//         uint ETH = minETH + _ETH % (actorBalance - minETH);
//         return ETH;
//     }

//     function getAdjustedR(uint ETH, uint _rAmount, uint ratio) internal view returns (uint) {
//         uint price = priceFeedTestnet.getPrice();
//         uint rAmount = _rAmount;
//         uint compositeDebt = rAmount + R_GAS_COMPENSATION;
//         uint ICR = LiquityMath._computeCR(ETH, compositeDebt, price);
//         if (ICR < ratio) {
//             compositeDebt = ETH * price / ratio;
//             rAmount = compositeDebt - R_GAS_COMPENSATION;
//         }
//         return rAmount;
//     }

//     function openTroveExt(uint _i, uint _ETH, uint _rAmount) public {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         EchidnaProxy echidnaProxy = echidnaProxies[actor];
//         uint actorBalance = address(echidnaProxy).balance;

//         // we pass in CCR instead of MCR in case it’s the first one
//         uint ETH = getAdjustedETH(actorBalance, _ETH, CCR);
//         uint rAmount = getAdjustedR(ETH, _rAmount, CCR);

//         //console.log('ETH', ETH);
//         //console.log('rAmount', rAmount);

//         echidnaProxy.openTrovePrx(ETH, rAmount, address(0), address(0), 0);

//         numberOfTroves = troveManager.getTroveOwnersCount();
//         assert(numberOfTroves > 0);
//         // canary
//         //assert(numberOfTroves == 0);
//     }

//     function openTroveRawExt(uint _i, uint _ETH, uint _rAmount, address _upperHint, address _lowerHint, uint _maxFee) public {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].openTrovePrx(_ETH, _rAmount, _upperHint, _lowerHint, _maxFee);
//     }

//     function addCollExt(uint _i, uint _ETH) external {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         EchidnaProxy echidnaProxy = echidnaProxies[actor];
//         uint actorBalance = address(echidnaProxy).balance;

//         uint ETH = getAdjustedETH(actorBalance, _ETH, MCR);

//         echidnaProxy.addCollPrx(ETH, address(0), address(0));
//     }

//     function addCollRawExt(uint _i, uint _ETH, address _upperHint, address _lowerHint) external {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].addCollPrx(_ETH, _upperHint, _lowerHint);
//     }

//     function withdrawCollExt(uint _i, uint _amount, address _upperHint, address _lowerHint) external {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].withdrawCollPrx(_amount, _upperHint, _lowerHint);
//     }

//     function withdrawRExt(uint _i, uint _amount, address _upperHint, address _lowerHint, uint _maxFee) external {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].withdrawRPrx(_amount, _upperHint, _lowerHint, _maxFee);
//     }

//     function repayRExt(uint _i, uint _amount, address _upperHint, address _lowerHint) external {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].repayRPrx(_amount, _upperHint, _lowerHint);
//     }

//     function closeTroveExt(uint _i) external {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].closeTrovePrx();
//     }

//     function adjustTroveExt(uint _i, uint _ETH, uint _collWithdrawal, uint _debtChange, bool _isDebtIncrease) external {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         EchidnaProxy echidnaProxy = echidnaProxies[actor];
//         uint actorBalance = address(echidnaProxy).balance;

//         uint ETH = getAdjustedETH(actorBalance, _ETH, MCR);
//         uint debtChange = _debtChange;
//         if (_isDebtIncrease) {
//             // TODO: add current amount already withdrawn:
//             debtChange = getAdjustedR(ETH, uint(_debtChange), MCR);
//         }
//         // TODO: collWithdrawal, debtChange
//         echidnaProxy.adjustTrovePrx(ETH, _collWithdrawal, debtChange, _isDebtIncrease, address(0), address(0), 0);
//     }

//     function adjustTroveRawExt(uint _i, uint _ETH, uint _collWithdrawal, uint _debtChange, bool _isDebtIncrease, address _upperHint, address _lowerHint, uint _maxFee) external {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].adjustTrovePrx(_ETH, _collWithdrawal, _debtChange, _isDebtIncrease, _upperHint, _lowerHint, _maxFee);
//     }

//     // Pool Manager

//     function provideToSPExt(uint _i, uint _amount) external {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].provideToSPPrx(_amount);
//     }

//     function withdrawFromSPExt(uint _i, uint _amount) external {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].withdrawFromSPPrx(_amount);
//     }

//     // R Token

//     function transferExt(uint _i, address recipient, uint256 amount) external returns (bool) {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].transferPrx(recipient, amount);
//     }

//     function approveExt(uint _i, address spender, uint256 amount) external returns (bool) {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].approvePrx(spender, amount);
//     }

//     function transferFromExt(uint _i, address sender, address recipient, uint256 amount) external returns (bool) {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].transferFromPrx(sender, recipient, amount);
//     }

//     function increaseAllowanceExt(uint _i, address spender, uint256 addedValue) external returns (bool) {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].increaseAllowancePrx(spender, addedValue);
//     }

//     function decreaseAllowanceExt(uint _i, address spender, uint256 subtractedValue) external returns (bool) {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].decreaseAllowancePrx(spender, subtractedValue);
//     }

//     // PriceFeed

//     function setPriceExt(uint256 _price) external {
//         bool result = priceFeedTestnet.setPrice(_price);
//         assert(result);
//     }

//     // --------------------------
//     // Invariants and properties
//     // --------------------------

//     function echidna_canary_number_of_troves() public view returns(bool) {
//         if (numberOfTroves > 20) {
//             return false;
//         }

//         return true;
//     }

//     function echidna_canary_active_pool_balance() public view returns(bool) {
//         if (address(activePool).balance > 0) {
//             return false;
//         }
//         return true;
//     }

//     function echidna_troves_order() external view returns(bool) {
//         address currentTrove = sortedTroves.getFirst();
//         address nextTrove = sortedTroves.getNext(currentTrove);

//         while (currentTrove != address(0) && nextTrove != address(0)) {
//             if (troveManager.getNominalICR(nextTrove) > troveManager.getNominalICR(currentTrove)) {
//                 return false;
//             }
//             // Uncomment to check that the condition is meaningful
//             //else return false;

//             currentTrove = nextTrove;
//             nextTrove = sortedTroves.getNext(currentTrove);
//         }

//         return true;
//     }

//     /**
//      * Status
//      * Minimum debt (gas compensation)
//      * Stake > 0
//      */
//     function echidna_trove_properties() public view returns(bool) {
//         address currentTrove = sortedTroves.getFirst();
//         while (currentTrove != address(0)) {
//             // Status
//             if (TroveManager.Status(troveManager.getTroveStatus(currentTrove)) != TroveManager.Status.active) {
//                 return false;
//             }
//             // Uncomment to check that the condition is meaningful
//             //else return false;

//             // Minimum debt (gas compensation)
//             if (troveManager.getTroveDebt(currentTrove) < R_GAS_COMPENSATION) {
//                 return false;
//             }
//             // Uncomment to check that the condition is meaningful
//             //else return false;

//             // Stake > 0
//             if (troveManager.getTroveStake(currentTrove) == 0) {
//                 return false;
//             }
//             // Uncomment to check that the condition is meaningful
//             //else return false;

//             currentTrove = sortedTroves.getNext(currentTrove);
//         }
//         return true;
//     }

//     function echidna_ETH_balances() public view returns(bool) {
//         if (address(troveManager).balance > 0) {
//             return false;
//         }

//         if (address(borrowerOperations).balance > 0) {
//             return false;
//         }

//         if (address(activePool).balance != activePool.collateralBalance()) {
//             return false;
//         }

//         if (address(defaultPool).balance != defaultPool.collateralBalance()) {
//             return false;
//         }

//         if (address(stabilityPool).balance != stabilityPool.collateralBalance()) {
//             return false;
//         }

//         if (address(rToken).balance > 0) {
//             return false;
//         }

//         if (address(priceFeedTestnet).balance > 0) {
//             return false;
//         }

//         if (address(sortedTroves).balance > 0) {
//             return false;
//         }

//         return true;
//     }

//     // TODO: What should we do with this? Should it be allowed? Should it be a canary?
//     function echidna_price() public view returns(bool) {
//         uint price = priceFeedTestnet.getPrice();

//         if (price == 0) {
//             return false;
//         }
//         // Uncomment to check that the condition is meaningful
//         //else return false;

//         return true;
//     }

//     // Total R matches
//     function echidna_R_global_balances() public view returns(bool) {
//         uint totalSupply = rToken.totalSupply();
//         uint borrowerOperationsBalance = rToken.balanceOf(address(borrowerOperations));

//         uint activePoolBalance = activePool.getRDebt();
//         uint defaultPoolBalance = defaultPool.getRDebt();
//         if (totalSupply != activePoolBalance + defaultPoolBalance) {
//             return false;
//         }

//         uint stabilityPoolBalance = stabilityPool.getTotalRDeposits();
//         address currentTrove = sortedTroves.getFirst();
//         uint trovesBalance;
//         while (currentTrove != address(0)) {
//             trovesBalance += rToken.balanceOf(address(currentTrove));
//             currentTrove = sortedTroves.getNext(currentTrove);
//         }
//         // we cannot state equality because tranfers are made to external addresses too
//         if (totalSupply <= stabilityPoolBalance + trovesBalance + borrowerOperationsBalance) {
//             return false;
//         }

//         return true;
//     }

//     /*
//     function echidna_test() public view returns(bool) {
//         return true;
//     }
//     */
// }
