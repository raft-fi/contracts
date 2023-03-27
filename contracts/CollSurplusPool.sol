// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Dependencies/ActivePoolDependent.sol";
import "./Dependencies/BorrowerOperationsDependent.sol";
import "./Dependencies/TroveManagerDependent.sol";
import "./CollateralPool.sol";

contract CollSurplusPool is Ownable2Step, CollateralPool, ActivePoolDependent, BorrowerOperationsDependent, TroveManagerDependent, ICollSurplusPool {
    string constant public NAME = "CollSurplusPool";

    // Collateral surplus claimable by trove owners
    mapping (address => uint) internal balances;

    // --- Constructor ---
    constructor(IERC20 _collateralToken) CollateralPool(_collateralToken) {
    }

    // --- Contract setters ---

    function setAddresses(
        IBorrowerOperations _borrowerOperations,
        ITroveManager _troveManager,
        IActivePool _activePool
    )
        external
        override
        onlyOwner
    {
        setBorrowerOperations(_borrowerOperations);
        setTroveManager(_troveManager);
        setActivePool(_activePool);

        renounceOwnership();
    }

    function getCollateral(address _account) external view override returns (uint) {
        return balances[_account];
    }

    // --- Pool functionality ---

    function depositCollateral(address _from, uint _amount) external override {
        if (msg.sender != address(activePool) && msg.sender != address(troveManager)) {
            revert CollSurplusPoolInvalidCaller();
        }
        _depositCollateral(_from, _amount);
    }

    function accountSurplus(address _account, uint _amount) external override onlyTroveManager {
        uint newAmount = balances[_account] + _amount;
        balances[_account] = newAmount;

        emit CollBalanceUpdated(_account, newAmount);
    }

    function claimColl(address _account) external override onlyBorrowerOperations {
        uint claimableColl = balances[_account];
        if (claimableColl == 0) {
            revert NoCollateralAvailable();
        }

        balances[_account] = 0;
        emit CollBalanceUpdated(_account, 0);

        ETH -= claimableColl;
        emit EtherSent(_account, claimableColl);

        collateralToken.transfer(_account, claimableColl);
    }
}
