// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import './Interfaces/IDefaultPool.sol';
import "./Dependencies/CheckContract.sol";

/*
 * The Default Pool holds the ETH and R debt (but not R tokens) from liquidations that have been redistributed
 * to active troves but not yet "applied", i.e. not yet recorded on a recipient active trove's struct.
 *
 * When a trove makes an operation that applies its pending ETH and R debt, its pending ETH and R debt is moved
 * from the Default Pool to the Active Pool.
 */
contract DefaultPool is Ownable2Step, CheckContract, IDefaultPool {
    string constant public NAME = "DefaultPool";

    address immutable public override collateralToken;

    address public troveManagerAddress;
    uint256 internal ETH;  // deposited ETH tracker
    uint256 internal rDebt;  // debt

    // --- Constructor ---
    constructor(address _collateralToken) {
        checkContract(_collateralToken);

        collateralToken = _collateralToken;

        emit CollateralTokenAddressSet(_collateralToken);
    }

    // --- Dependency setters ---

    function setAddresses(
        address _troveManagerAddress
    )
        external
        onlyOwner
    {
        checkContract(_troveManagerAddress);

        troveManagerAddress = _troveManagerAddress;

        emit TroveManagerAddressChanged(_troveManagerAddress);

        renounceOwnership();
    }

    // --- Getters for public variables. Required by IPool interface ---

    /*
    * Returns the ETH state variable.
    *
    * Not necessarily equal to the the contract's raw ETH balance - ether can be forcibly sent to contracts.
    */
    function getETH() external view override returns (uint) {
        return ETH;
    }

    function getRDebt() external view override returns (uint) {
        return rDebt;
    }

    // --- Pool functionality ---

    function depositCollateral(address _from, uint _amount) external override {
        _requireCallerIsTroveManager();

        IERC20(collateralToken).transferFrom(_from, address(this), _amount);
        ETH += _amount;

        emit DefaultPoolETHBalanceUpdated(ETH);
    }

    function sendETH(address _to, uint _amount) external override {
        _requireCallerIsTroveManager();
        ETH -= _amount;
        emit DefaultPoolETHBalanceUpdated(ETH);
        emit EtherSent(_to, _amount);
        IERC20(collateralToken).transfer(_to, _amount);
    }

    function increaseRDebt(uint _amount) external override {
        _requireCallerIsTroveManager();
        rDebt += _amount;
        emit DefaultPoolRDebtUpdated(rDebt);
    }

    function decreaseRDebt(uint _amount) external override {
        _requireCallerIsTroveManager();
        rDebt -= _amount;
        emit DefaultPoolRDebtUpdated(rDebt);
    }

    // --- 'require' functions ---

    function _requireCallerIsTroveManager() internal view {
        require(msg.sender == troveManagerAddress, "DefaultPool: Caller is not the TroveManager");
    }
}
