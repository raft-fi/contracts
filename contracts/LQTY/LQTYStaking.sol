// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../Dependencies/BaseMath.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/CheckContract.sol";
import "../Interfaces/ILQTYToken.sol";
import "../Interfaces/ILQTYStaking.sol";
import "../Dependencies/LiquityMath.sol";
import "../Interfaces/ILUSDToken.sol";

contract LQTYStaking is ILQTYStaking, Ownable, CheckContract, BaseMath {
    // --- Data ---
    string public constant NAME = "LQTYStaking";

    mapping(address => uint256) public stakes;
    uint256 public totalLQTYStaked;

    uint256 public F_ETH; // Running sum of ETH fees per-LQTY-staked
    uint256 public F_LUSD; // Running sum of LQTY fees per-LQTY-staked

    // User snapshots of F_ETH and F_LUSD, taken at the point at which their latest deposit was made
    mapping(address => Snapshot) public snapshots;

    struct Snapshot {
        uint256 F_ETH_Snapshot;
        uint256 F_LUSD_Snapshot;
    }

    ILQTYToken public lqtyToken;
    ILUSDToken public lusdToken;

    address public troveManagerAddress;
    address public borrowerOperationsAddress;
    address public activePoolAddress;

    // --- Functions ---

    function setAddresses(
        address _lqtyTokenAddress,
        address _lusdTokenAddress,
        address _troveManagerAddress,
        address _borrowerOperationsAddress,
        address _activePoolAddress
    ) external override onlyOwner {
        checkContract(_lqtyTokenAddress);
        checkContract(_lusdTokenAddress);
        checkContract(_troveManagerAddress);
        checkContract(_borrowerOperationsAddress);
        checkContract(_activePoolAddress);

        lqtyToken = ILQTYToken(_lqtyTokenAddress);
        lusdToken = ILUSDToken(_lusdTokenAddress);
        troveManagerAddress = _troveManagerAddress;
        borrowerOperationsAddress = _borrowerOperationsAddress;
        activePoolAddress = _activePoolAddress;

        emit LQTYTokenAddressSet(_lqtyTokenAddress);
        emit LQTYTokenAddressSet(_lusdTokenAddress);
        emit TroveManagerAddressSet(_troveManagerAddress);
        emit BorrowerOperationsAddressSet(_borrowerOperationsAddress);
        emit ActivePoolAddressSet(_activePoolAddress);

        _renounceOwnership();
    }

    // If caller has a pre-existing stake, send any accumulated ETH and LUSD gains to them.
    function stake(uint256 _LQTYamount) external override {
        _requireNonZeroAmount(_LQTYamount);

        uint256 currentStake = stakes[msg.sender];

        uint256 ETHGain;
        uint256 LUSDGain;
        // Grab any accumulated ETH and LUSD gains from the current stake
        if (currentStake != 0) {
            ETHGain = _getPendingETHGain(msg.sender);
            LUSDGain = _getPendingLUSDGain(msg.sender);
        }

        _updateUserSnapshots(msg.sender);

        uint256 newStake = currentStake + _LQTYamount;

        // Increase user’s stake and total LQTY staked
        stakes[msg.sender] = newStake;
        totalLQTYStaked += _LQTYamount;
        emit TotalLQTYStakedUpdated(totalLQTYStaked);

        // Transfer LQTY from caller to this contract
        lqtyToken.sendToLQTYStaking(msg.sender, _LQTYamount);

        emit StakeChanged(msg.sender, newStake);
        emit StakingGainsWithdrawn(msg.sender, LUSDGain, ETHGain);

        // Send accumulated LUSD and ETH gains to the caller
        if (currentStake != 0) {
            lusdToken.transfer(msg.sender, LUSDGain);
            _sendETHGainToUser(ETHGain);
        }
    }

    // Unstake the LQTY and send the it back to the caller, along with their accumulated LUSD & ETH gains.
    // If requested amount > stake, send their entire stake.
    function unstake(uint256 _LQTYamount) external override {
        uint256 currentStake = stakes[msg.sender];
        _requireUserHasStake(currentStake);

        // Grab any accumulated ETH and LUSD gains from the current stake
        uint256 ETHGain = _getPendingETHGain(msg.sender);
        uint256 LUSDGain = _getPendingLUSDGain(msg.sender);

        _updateUserSnapshots(msg.sender);

        if (_LQTYamount > 0) {
            uint256 LQTYToWithdraw = LiquityMath._min(_LQTYamount, currentStake);

            uint256 newStake = currentStake - LQTYToWithdraw;

            // Decrease user's stake and total LQTY staked
            stakes[msg.sender] = newStake;
            totalLQTYStaked = totalLQTYStaked - LQTYToWithdraw;
            emit TotalLQTYStakedUpdated(totalLQTYStaked);

            // Transfer unstaked LQTY to user
            lqtyToken.transfer(msg.sender, LQTYToWithdraw);

            emit StakeChanged(msg.sender, newStake);
        }

        emit StakingGainsWithdrawn(msg.sender, LUSDGain, ETHGain);

        // Send accumulated LUSD and ETH gains to the caller
        lusdToken.transfer(msg.sender, LUSDGain);
        _sendETHGainToUser(ETHGain);
    }

    // --- Reward-per-unit-staked increase functions. Called by Liquity core contracts ---

    function increaseF_ETH(uint256 _ETHFee) external override {
        _requireCallerIsTroveManager();
        uint256 ETHFeePerLQTYStaked;

        if (totalLQTYStaked > 0) ETHFeePerLQTYStaked = _ETHFee * DECIMAL_PRECISION / totalLQTYStaked;

        F_ETH += ETHFeePerLQTYStaked;
        emit F_ETHUpdated(F_ETH);
    }

    function increaseF_LUSD(uint256 _LUSDFee) external override {
        _requireCallerIsBorrowerOperations();
        uint256 LUSDFeePerLQTYStaked;

        if (totalLQTYStaked > 0) LUSDFeePerLQTYStaked = _LUSDFee * DECIMAL_PRECISION / totalLQTYStaked;

        F_LUSD += LUSDFeePerLQTYStaked;
        emit F_LUSDUpdated(F_LUSD);
    }

    // --- Pending reward functions ---

    function getPendingETHGain(address _user) external view override returns (uint256) {
        return _getPendingETHGain(_user);
    }

    function _getPendingETHGain(address _user) internal view returns (uint256) {
        uint256 F_ETH_Snapshot = snapshots[_user].F_ETH_Snapshot;
        uint256 ETHGain = stakes[_user] * (F_ETH - F_ETH_Snapshot) / DECIMAL_PRECISION;
        return ETHGain;
    }

    function getPendingLUSDGain(address _user) external view override returns (uint256) {
        return _getPendingLUSDGain(_user);
    }

    function _getPendingLUSDGain(address _user) internal view returns (uint256) {
        uint256 F_LUSD_Snapshot = snapshots[_user].F_LUSD_Snapshot;
        uint256 LUSDGain = stakes[_user] * (F_LUSD - F_LUSD_Snapshot) / DECIMAL_PRECISION;
        return LUSDGain;
    }

    // --- Internal helper functions ---

    function _updateUserSnapshots(address _user) internal {
        snapshots[_user].F_ETH_Snapshot = F_ETH;
        snapshots[_user].F_LUSD_Snapshot = F_LUSD;
        emit StakerSnapshotsUpdated(_user, F_ETH, F_LUSD);
    }

    function _sendETHGainToUser(uint256 ETHGain) internal {
        emit EtherSent(msg.sender, ETHGain);
        (bool success,) = msg.sender.call{value: ETHGain}("");
        require(success, "LQTYStaking: Failed to send accumulated ETHGain");
    }

    // --- 'require' functions ---

    function _requireCallerIsTroveManager() internal view {
        require(msg.sender == troveManagerAddress, "LQTYStaking: caller is not TroveM");
    }

    function _requireCallerIsBorrowerOperations() internal view {
        require(msg.sender == borrowerOperationsAddress, "LQTYStaking: caller is not BorrowerOps");
    }

    function _requireCallerIsActivePool() internal view {
        require(msg.sender == activePoolAddress, "LQTYStaking: caller is not ActivePool");
    }

    function _requireUserHasStake(uint256 currentStake) internal pure {
        require(currentStake > 0, "LQTYStaking: User must have a non-zero stake");
    }

    function _requireNonZeroAmount(uint256 _amount) internal pure {
        require(_amount > 0, "LQTYStaking: Amount must be non-zero");
    }

    receive() external payable {
        _requireCallerIsActivePool();
    }
}
