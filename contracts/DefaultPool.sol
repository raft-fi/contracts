// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import './Interfaces/IDefaultPool.sol';
import "./Dependencies/PositionManagerDependent.sol";
import "./CollateralPool.sol";

/*
 * The Default Pool holds the CollateralToken and R debt (but not R tokens) from liquidations that have been redistributed
 * to active positions but not yet "applied", i.e. not yet recorded on a recipient active position's struct.
 *
 * When a position makes an operation that applies its pending collateralToken and R debt, its pending collateralToken and R debt is moved
 * from the Default Pool to the Active Pool.
 */
contract DefaultPool is Ownable2Step, CollateralPool, PositionManagerDependent, IDefaultPool {
    string constant public NAME = "DefaultPool";

    uint256 public override rDebt;

    // --- Constructor ---
    constructor(IERC20 _collateralToken) CollateralPool(_collateralToken) {
    }

    // --- Dependency setters ---

    function setAddresses(IPositionManager _positionManager) external onlyOwner {
        setPositionManager(_positionManager);

        renounceOwnership();
    }

    // --- Pool functionality ---

    function depositCollateral(address _from, uint _amount) external override onlyPositionManager {
        _depositCollateral(_from, _amount);

        emit DefaultPoolCollateralTokenBalanceUpdated(collateralBalance);
    }

    function withdrawCollateral(address _to, uint _amount) external override onlyPositionManager {
        collateralBalance -= _amount;
        emit DefaultPoolCollateralTokenBalanceUpdated(collateralBalance);
        emit CollateralTokenSent(_to, _amount);
        collateralToken.transfer(_to, _amount);
    }

    function increaseRDebt(uint _amount) external override onlyPositionManager {
        rDebt += _amount;
        emit DefaultPoolRDebtUpdated(rDebt);
    }

    function decreaseRDebt(uint _amount) external override onlyPositionManager {
        rDebt -= _amount;
        emit DefaultPoolRDebtUpdated(rDebt);
    }
}
