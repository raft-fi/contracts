// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../Interfaces/ILQTYToken.sol";

/*
* The lockup contract architecture utilizes a single LockupContract, with an unlockTime. The unlockTime is passed as an argument
* to the LockupContract's constructor. The contract's balance can be withdrawn by the beneficiary when block.timestamp > unlockTime.
* At construction, the contract checks that unlockTime is at least one year later than the Liquity system's deployment time.

* Within the first year from deployment, the deployer of the LQTYToken (Liquity AG's address) may transfer LQTY only to valid
* LockupContracts, and no other addresses (this is enforced in LQTYToken.sol's transfer() function).
*
* The above two restrictions ensure that until one year after system deployment, LQTY tokens originating from Liquity AG cannot
* enter circulating supply and cannot be staked to earn system revenue.
*/
contract LockupContract {

    // --- Data ---
    string public constant NAME = "LockupContract";

    uint256 public constant SECONDS_IN_ONE_YEAR = 31536000;

    address public immutable beneficiary;

    ILQTYToken public lqtyToken;

    // Unlock time is the Unix point in time at which the beneficiary can withdraw.
    uint256 public unlockTime;

    // --- Events ---

    event LockupContractCreated(address _beneficiary, uint256 _unlockTime);
    event LockupContractEmptied(uint256 _LQTYwithdrawal);

    // --- Functions ---

    constructor(address _lqtyTokenAddress, address _beneficiary, uint256 _unlockTime) {
        lqtyToken = ILQTYToken(_lqtyTokenAddress);

        /*
        * Set the unlock time to a chosen instant in the future, as long as it is at least 1 year after
        * the system was deployed
        */
        _requireUnlockTimeIsAtLeastOneYearAfterSystemDeployment(_unlockTime);
        unlockTime = _unlockTime;

        beneficiary = _beneficiary;
        emit LockupContractCreated(_beneficiary, _unlockTime);
    }

    function withdrawLQTY() external {
        _requireCallerIsBeneficiary();
        _requireLockupDurationHasPassed();

        ILQTYToken lqtyTokenCached = lqtyToken;
        uint256 LQTYBalance = lqtyTokenCached.balanceOf(address(this));
        lqtyTokenCached.transfer(beneficiary, LQTYBalance);
        emit LockupContractEmptied(LQTYBalance);
    }

    // --- 'require' functions ---

    function _requireCallerIsBeneficiary() internal view {
        require(msg.sender == beneficiary, "LockupContract: caller is not the beneficiary");
    }

    function _requireLockupDurationHasPassed() internal view {
        require(block.timestamp >= unlockTime, "LockupContract: The lockup duration must have passed");
    }

    function _requireUnlockTimeIsAtLeastOneYearAfterSystemDeployment(uint256 _unlockTime) internal view {
        uint256 systemDeploymentTime = lqtyToken.getDeploymentStartTime();
        require(
            _unlockTime >= (systemDeploymentTime + SECONDS_IN_ONE_YEAR),
            "LockupContract: unlock time must be at least one year after system deployment"
        );
    }
}
