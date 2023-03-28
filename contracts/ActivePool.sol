// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Interfaces/IActivePool.sol";
import "./Dependencies/BorrowerOperationsDependent.sol";
import "./Dependencies/DefaultPoolDependent.sol";
import "./Dependencies/TroveManagerDependent.sol";
import "./CollateralPool.sol";

/*
 * The Active Pool holds the collateral tokens and R debt (but not R tokens) for all active troves.
 *
 * When a trove is liquidated, it's collateral tokens and R debt are transferred from the Active Pool, to either the
 * the Default Pool or the liquidator, depending on the liquidation conditions.
 *
 */
contract ActivePool is Ownable2Step, CollateralPool, BorrowerOperationsDependent, DefaultPoolDependent, TroveManagerDependent, IActivePool {
    string constant public NAME = "ActivePool";

    address public defaultPoolAddress;
    uint256 internal rDebt;

    modifier onlyBorrowerOperationsOrTroveManager() {
        if (msg.sender != address(borrowerOperations) && msg.sender != address(troveManager)) {
            revert ActivePoolInvalidCaller();
        }
        _;
    }

    // --- Constructor ---
    constructor(IERC20 _collateralToken) CollateralPool(_collateralToken) {
    }

    // --- Contract setters ---

    function setAddresses(
        IBorrowerOperations _borrowerOperations,
        ITroveManager _troveManager,
        IDefaultPool _defaultPool
    )
        external
        onlyOwner
    {
        setBorrowerOperations(_borrowerOperations);
        setTroveManager(_troveManager);
        setDefaultPool(_defaultPool);

        renounceOwnership();
    }

    // --- Getters for public variables. Required by IPool interface ---

    function getRDebt() external view override returns (uint) {
        return rDebt;
    }

    // --- Pool functionality ---

    function depositCollateral(
        address _from,
        uint _amount
    )
        external
        override
        onlyBorrowerOperationsOrTroveManager
    {
        _depositCollateral(_from, _amount);

        emit ActivePoolCollateralTokenBalanceUpdated(collateralBalance);
    }

    function withdrawCollateral(address _account, uint _amount) external override onlyBorrowerOperationsOrTroveManager {
        collateralBalance -= _amount;
        emit ActivePoolCollateralTokenBalanceUpdated(collateralBalance);
        emit CollateralTokenSent(_account, _amount);
        collateralToken.transfer(_account, _amount);
    }

    function increaseRDebt(uint _amount) external override onlyBorrowerOperationsOrTroveManager {
        rDebt += _amount;
        emit ActivePoolRDebtUpdated(rDebt);
    }

    function decreaseRDebt(uint _amount) external override onlyBorrowerOperationsOrTroveManager {
        rDebt -= _amount;
        emit ActivePoolRDebtUpdated(rDebt);
    }
}
