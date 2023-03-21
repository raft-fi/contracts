// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;


interface IUnipool {
    event LQTYTokenAddressChanged(address _lqtyTokenAddress);
    event UniTokenAddressChanged(address _uniTokenAddress);
    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    function setParams(address _lqtyTokenAddress, address _uniTokenAddress, uint256 _duration) external;
    function lastTimeRewardApplicable() external view returns (uint256);
    function rewardPerToken() external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function withdrawAndClaim() external;
    function claimReward() external;
    //function notifyRewardAmount(uint256 reward) external;
}
