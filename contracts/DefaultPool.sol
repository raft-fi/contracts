// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./Interfaces/IDefaultPool.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";

/*
 * The Default Pool holds the ETH and LUSD debt (but not LUSD tokens) from liquidations that have been redistributed
 * to active troves but not yet "applied", i.e. not yet recorded on a recipient active trove's struct.
 *
 * When a trove makes an operation that applies its pending ETH and LUSD debt, its pending ETH and LUSD debt is moved
 * from the Default Pool to the Active Pool.
 */
contract DefaultPool is Ownable, CheckContract, IDefaultPool {
    string public constant NAME = "DefaultPool";

    address public troveManagerAddress;
    address public activePoolAddress;
    uint256 internal ETH; // deposited ETH tracker
    uint256 internal LUSDDebt; // debt

    // --- Dependency setters ---

    function setAddresses(address _troveManagerAddress, address _activePoolAddress) external onlyOwner {
        checkContract(_troveManagerAddress);
        checkContract(_activePoolAddress);

        troveManagerAddress = _troveManagerAddress;
        activePoolAddress = _activePoolAddress;

        emit TroveManagerAddressChanged(_troveManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);

        _renounceOwnership();
    }

    // --- Getters for public variables. Required by IPool interface ---

    /*
    * Returns the ETH state variable.
    *
    * Not necessarily equal to the the contract's raw ETH balance - ether can be forcibly sent to contracts.
    */
    function getETH() external view override returns (uint256) {
        return ETH;
    }

    function getLUSDDebt() external view override returns (uint256) {
        return LUSDDebt;
    }

    // --- Pool functionality ---

    function sendETHToActivePool(uint256 _amount) external override {
        _requireCallerIsTroveManager();
        address activePool = activePoolAddress; // cache to save an SLOAD
        ETH -= _amount;
        emit DefaultPoolETHBalanceUpdated(ETH);
        emit EtherSent(activePool, _amount);

        (bool success,) = activePool.call{value: _amount}("");
        require(success, "DefaultPool: sending ETH failed");
    }

    function increaseLUSDDebt(uint256 _amount) external override {
        _requireCallerIsTroveManager();
        LUSDDebt += _amount;
        emit DefaultPoolLUSDDebtUpdated(LUSDDebt);
    }

    function decreaseLUSDDebt(uint256 _amount) external override {
        _requireCallerIsTroveManager();
        LUSDDebt -= _amount;
        emit DefaultPoolLUSDDebtUpdated(LUSDDebt);
    }

    // --- 'require' functions ---

    function _requireCallerIsActivePool() internal view {
        require(msg.sender == activePoolAddress, "DefaultPool: Caller is not the ActivePool");
    }

    function _requireCallerIsTroveManager() internal view {
        require(msg.sender == troveManagerAddress, "DefaultPool: Caller is not the TroveManager");
    }

    // --- Fallback function ---

    receive() external payable {
        _requireCallerIsActivePool();
        ETH += msg.value;
        emit DefaultPoolETHBalanceUpdated(ETH);
    }
}
