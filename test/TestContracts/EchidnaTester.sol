// // SPDX-License-Identifier: MIT

// pragma solidity 0.8.19;

// import "../PositionManager.sol";
// import "../BorrowerOperations.sol";
// import "../ActivePool.sol";
// import "../DefaultPool.sol";
// import "../StabilityPool.sol";
// import "../RToken.sol";
// import "./PriceFeedTestnet.sol";
// import "../SortedPositions.sol";
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

//     PositionManager public positionManager;
//     BorrowerOperations public borrowerOperations;
//     ActivePool public activePool;
//     DefaultPool public defaultPool;
//     StabilityPool public stabilityPool;
//     RToken public rToken;
//     WstETHTokenMock public collateralToken;
//     PriceFeedTestnet priceFeedTestnet;
//     SortedPositions sortedPositions;

//     EchidnaProxy[NUMBER_OF_ACTORS] public echidnaProxies;

//     uint private numberOfPositions;

//     constructor() public {
//         positionManager = new PositionManager();
//         borrowerOperations = new BorrowerOperations();
//         collateralToken = new WstETHTokenMock();
//         activePool = new ActivePool(address(collateralToken));
//         defaultPool = new DefaultPool(address(collateralToken));
//         stabilityPool = new StabilityPool(address(collateralToken));
//         rToken = new RToken(
//             address(positionManager),
//             address(stabilityPool),
//             address(borrowerOperations)
//         );

//         priceFeedTestnet = new PriceFeedTestnet();

//         sortedPositions = new SortedPositions();

//         positionManager.setAddresses(address(borrowerOperations),
//             address(activePool), address(defaultPool),
//             address(stabilityPool),
//             address(priceFeedTestnet), address(rToken),
//             address(sortedPositions), address(0), address(0));

//         borrowerOperations.setAddresses(address(positionManager),
//             address(activePool), address(defaultPool),
//             address(stabilityPool),
//             address(priceFeedTestnet), address(sortedPositions),
//             address(rToken), address(0));

//         activePool.setAddresses(address(borrowerOperations),
//             address(positionManager), address(stabilityPool), address(defaultPool));

//         defaultPool.setAddresses(address(positionManager));

//         stabilityPool.setAddresses(address(borrowerOperations),
//             address(positionManager), address(activePool), address(rToken),
//             address(sortedPositions), address(priceFeedTestnet), address(0));

//         sortedPositions.setParams(1e18, address(positionManager), address(borrowerOperations));

//         for (uint i = 0; i < NUMBER_OF_ACTORS; i++) {
//             echidnaProxies[i] = new EchidnaProxy(positionManager, borrowerOperations, stabilityPool, rToken);
//             (bool success, ) = address(echidnaProxies[i]).call{value: INITIAL_BALANCE}("");
//             require(success);
//         }

//         MCR = borrowerOperations.MCR();
//         R_GAS_COMPENSATION = borrowerOperations.R_GAS_COMPENSATION();
//         require(MCR > 0);

//         // TODO:
//         priceFeedTestnet.setPrice(1e22);
//     }

//     // PositionManager

//     function liquidateExt(uint _i, address _user) external {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].liquidatePrx(_user);
//     }

//     function liquidatePositionsExt(uint _i, uint _n) external {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].liquidatePositionsPrx(_n);
//     }

//     function batchLiquidatePositionsExt(uint _i, address[] calldata _positionArray) external {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].batchLiquidatePositionsPrx(_positionArray);
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

//     function openPositionExt(uint _i, uint _ETH, uint _rAmount) public {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         EchidnaProxy echidnaProxy = echidnaProxies[actor];
//         uint actorBalance = address(echidnaProxy).balance;

//         // we pass in CCR instead of MCR in case it’s the first one
//         uint ETH = getAdjustedETH(actorBalance, _ETH, CCR);
//         uint rAmount = getAdjustedR(ETH, _rAmount, CCR);

//         //console.log('ETH', ETH);
//         //console.log('rAmount', rAmount);

//         echidnaProxy.openPositionPrx(ETH, rAmount, address(0), address(0), 0);

//         numberOfPositions = positionManager.getPositionOwnersCount();
//         assert(numberOfPositions > 0);
//         // canary
//         //assert(numberOfPositions == 0);
//     }

//     function openPositionRawExt(uint _i, uint _ETH, uint _rAmount, address _upperHint, address _lowerHint, uint _maxFee) public {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].openPositionPrx(_ETH, _rAmount, _upperHint, _lowerHint, _maxFee);
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

//     function closePositionExt(uint _i) external {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].closePositionPrx();
//     }

//     function adjustPositionExt(uint _i, uint _ETH, uint _collWithdrawal, uint _debtChange, bool _isDebtIncrease) external {
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
//         echidnaProxy.adjustPositionPrx(ETH, _collWithdrawal, debtChange, _isDebtIncrease, address(0), address(0), 0);
//     }

//     function adjustPositionRawExt(uint _i, uint _ETH, uint _collWithdrawal, uint _debtChange, bool _isDebtIncrease, address _upperHint, address _lowerHint, uint _maxFee) external {
//         uint actor = _i % NUMBER_OF_ACTORS;
//         echidnaProxies[actor].adjustPositionPrx(_ETH, _collWithdrawal, _debtChange, _isDebtIncrease, _upperHint, _lowerHint, _maxFee);
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

//     function echidna_canary_number_of_positions() public view returns(bool) {
//         if (numberOfPositions > 20) {
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

//     function echidna_positions_order() external view returns(bool) {
//         address currentPosition = sortedPositions.getFirst();
//         address nextPosition = sortedPositions.getNext(currentPosition);

//         while (currentPosition != address(0) && nextPosition != address(0)) {
//             if (positionManager.getNominalICR(nextPosition) > positionManager.getNominalICR(currentPosition)) {
//                 return false;
//             }
//             // Uncomment to check that the condition is meaningful
//             //else return false;

//             currentPosition = nextPosition;
//             nextPosition = sortedPositions.getNext(currentPosition);
//         }

//         return true;
//     }

//     /**
//      * Status
//      * Minimum debt (gas compensation)
//      * Stake > 0
//      */
//     function echidna_position_properties() public view returns(bool) {
//         address currentPosition = sortedPositions.getFirst();
//         while (currentPosition != address(0)) {
//             // Status
//             if (PositionManager.Status(positionManager.getPositionStatus(currentPosition)) != PositionManager.Status.active) {
//                 return false;
//             }
//             // Uncomment to check that the condition is meaningful
//             //else return false;

//             // Minimum debt (gas compensation)
//             if (positionManager.getPositionDebt(currentPosition) < R_GAS_COMPENSATION) {
//                 return false;
//             }
//             // Uncomment to check that the condition is meaningful
//             //else return false;

//             // Stake > 0
//             if (positionManager.getPositionStake(currentPosition) == 0) {
//                 return false;
//             }
//             // Uncomment to check that the condition is meaningful
//             //else return false;

//             currentPosition = sortedPositions.getNext(currentPosition);
//         }
//         return true;
//     }

//     function echidna_ETH_balances() public view returns(bool) {
//         if (address(positionManager).balance > 0) {
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

//         if (address(sortedPositions).balance > 0) {
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

//         uint activePoolBalance = activePool.rDebt();
//         uint defaultPoolBalance = defaultPool.rDebt();
//         if (totalSupply != activePoolBalance + defaultPoolBalance) {
//             return false;
//         }

//         uint stabilityPoolBalance = stabilityPool.getTotalRDeposits();
//         address currentPosition = sortedPositions.getFirst();
//         uint positionsBalance;
//         while (currentPosition != address(0)) {
//             positionsBalance += rToken.balanceOf(address(currentPosition));
//             currentPosition = sortedPositions.getNext(currentPosition);
//         }
//         // we cannot state equality because tranfers are made to external addresses too
//         if (totalSupply <= stabilityPoolBalance + positionsBalance + borrowerOperationsBalance) {
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
