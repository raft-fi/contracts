// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import './Interfaces/IDefaultPool.sol';
import "./Dependencies/TroveManagerDependent.sol";
import "./CollateralPool.sol";

/*
 * The Default Pool holds the CollateralToken and R debt (but not R tokens) from liquidations that have been redistributed
 * to active troves but not yet "applied", i.e. not yet recorded on a recipient active trove's struct.
 *
 * When a trove makes an operation that applies its pending collateralToken and R debt, its pending collateralToken and R debt is moved
 * from the Default Pool to the Active Pool.
 */
contract DefaultPool is Ownable2Step, CollateralPool, TroveManagerDependent, IDefaultPool {
    string constant public NAME = "DefaultPool";

    uint256 internal rDebt;  // debt

    // --- Constructor ---
    constructor(IERC20 _collateralToken) CollateralPool(_collateralToken) {
    }

    // --- Dependency setters ---

    function setAddresses(ITroveManager _troveManager) external onlyOwner {
        setTroveManager(_troveManager);

        renounceOwnership();
    }

    // --- Getters for public variables. Required by IPool interface ---

    function getRDebt() external view override returns (uint) {
        return rDebt;
    }

    // --- Pool functionality ---

    function depositCollateral(address _from, uint _amount) external override onlyTroveManager {
        _depositCollateral(_from, _amount);

        emit DefaultPoolETHBalanceUpdated(collateralBalance);
    }

    function sendETH(address _to, uint _amount) external override onlyTroveManager {
        collateralBalance -= _amount;
        emit DefaultPoolETHBalanceUpdated(collateralBalance);
        emit EtherSent(_to, _amount);
        collateralToken.transfer(_to, _amount);
    }

    function increaseRDebt(uint _amount) external override onlyTroveManager {
        rDebt += _amount;
        emit DefaultPoolRDebtUpdated(rDebt);
    }

    function decreaseRDebt(uint _amount) external override onlyTroveManager {
        rDebt -= _amount;
        emit DefaultPoolRDebtUpdated(rDebt);
    }
}
