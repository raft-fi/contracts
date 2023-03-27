// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Interfaces/IActivePool.sol";
import "./Dependencies/CheckContract.sol";

/*
 * The Active Pool holds the collateral tokens and R debt (but not R tokens) for all active troves.
 *
 * When a trove is liquidated, it's collateral tokens and R debt are transferred from the Active Pool, to either the
 * the Default Pool or the liquidator, depending on the liquidation conditions.
 *
 */
contract ActivePool is Ownable2Step, CheckContract, IActivePool {
    string constant public NAME = "ActivePool";

    address immutable public override collateralToken;

    address public borrowerOperationsAddress;
    address public troveManagerAddress;
    address public defaultPoolAddress;
    uint256 internal ETH;  // deposited ether tracker
    uint256 internal rDebt;

    // --- Constructor ---
    constructor(address _collateralToken) {
        checkContract(_collateralToken);

        collateralToken = _collateralToken;

        emit CollateralTokenAddressSet(_collateralToken);
    }

    // --- Contract setters ---

    function setAddresses(
        address _borrowerOperationsAddress,
        address _troveManagerAddress,
        address _defaultPoolAddress
    )
        external
        onlyOwner
    {
        checkContract(_borrowerOperationsAddress);
        checkContract(_troveManagerAddress);
        checkContract(_defaultPoolAddress);

        borrowerOperationsAddress = _borrowerOperationsAddress;
        troveManagerAddress = _troveManagerAddress;
        defaultPoolAddress = _defaultPoolAddress;

        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit TroveManagerAddressChanged(_troveManagerAddress);
        emit DefaultPoolAddressChanged(_defaultPoolAddress);

        renounceOwnership();
    }

    // --- Getters for public variables. Required by IPool interface ---

    /*
    * Returns the ETH state variable.
    *
    *Not necessarily equal to the the contract's raw ETH balance - ether can be forcibly sent to contracts.
    */
    function getETH() external view override returns (uint) {
        return ETH;
    }

    function getRDebt() external view override returns (uint) {
        return rDebt;
    }

    // --- Pool functionality ---

    function depositCollateral(address _from, uint _amount) external override {
        _requireCallerIsBOorTroveM();

        IERC20(collateralToken).transferFrom(_from, address(this), _amount);
        ETH += _amount;

        emit ActivePoolETHBalanceUpdated(ETH);
    }

    function sendETH(address _account, uint _amount) external override {
        _requireCallerIsBOorTroveM();
        ETH -= _amount;
        emit ActivePoolETHBalanceUpdated(ETH);
        emit EtherSent(_account, _amount);
        IERC20(collateralToken).transfer(_account, _amount);
    }

    function increaseRDebt(uint _amount) external override {
        _requireCallerIsBOorTroveM();
        rDebt += _amount;
        emit ActivePoolRDebtUpdated(rDebt);
    }

    function decreaseRDebt(uint _amount) external override {
        _requireCallerIsBOorTroveM();
        rDebt -= _amount;
        emit ActivePoolRDebtUpdated(rDebt);
    }

    // --- 'require' functions ---

    function _requireCallerIsBOorTroveM() internal view {
        require(
            msg.sender == borrowerOperationsAddress ||
            msg.sender == troveManagerAddress,
            "ActivePool: Caller is neither BorrowerOperations nor TroveManager");
    }
}
