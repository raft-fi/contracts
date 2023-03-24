// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "./Interfaces/ILUSDToken.sol";
import "./Dependencies/CheckContract.sol";

/*
*
* --- Functionality added specific to the LUSDToken ---
*
* 1) Transfer protection: blacklist of addresses that are invalid recipients (i.e. core Liquity contracts) in external
* transfer() and transferFrom() calls. The purpose is to protect users from losing tokens by mistakenly sending LUSD directly to a Liquity
* core contract, when they should rather call the right function.
*
* 2) sendToPool() and returnFromPool(): functions callable only Liquity core contracts, which move LUSD tokens between Liquity <-> user.
*/

contract LUSDToken is ERC20Permit, CheckContract, ILUSDToken {
    // --- Addresses ---
    address public immutable troveManagerAddress;
    address public immutable borrowerOperationsAddress;

    constructor
    (
        address _troveManagerAddress,
        address _borrowerOperationsAddress
    )
        ERC20Permit("LUSD Stablecoin")
        ERC20("LUSD Stablecoin", "LUSD")
    {
        checkContract(_troveManagerAddress);
        checkContract(_borrowerOperationsAddress);

        troveManagerAddress = _troveManagerAddress;
        emit TroveManagerAddressChanged(_troveManagerAddress);

        borrowerOperationsAddress = _borrowerOperationsAddress;
        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
    }

    // --- Functions for intra-Liquity calls ---

    function mint(address _account, uint256 _amount) external override {
        _requireCallerIsBorrowerOperations();
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external override {
        _requireCallerIsBOorTroveM();
        _burn(_account, _amount);
    }

    function returnFromPool(address _poolAddress, address _receiver, uint256 _amount) external override {
        _requireCallerIsTroveManager();
        _transfer(_poolAddress, _receiver, _amount);
    }

    function _requireCallerIsBorrowerOperations() internal view {
        require(msg.sender == borrowerOperationsAddress, "LUSDToken: Caller is not BorrowerOperations");
    }

    function _requireCallerIsBOorTroveM() internal view {
        require(
            msg.sender == borrowerOperationsAddress ||
            msg.sender == troveManagerAddress,
            "LUSD: Caller is neither BorrowerOperations nor TroveManager"
        );
    }

    function _requireCallerIsTroveManager() internal view {
        require(
            msg.sender == troveManagerAddress,
            "LUSD: Caller is not TroveManager");
    }
}
