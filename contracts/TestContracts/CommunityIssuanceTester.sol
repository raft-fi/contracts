// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../LQTY/CommunityIssuance.sol";

contract CommunityIssuanceTester is CommunityIssuance {
    function obtainLQTY(uint256 _amount) external {
        lqtyToken.transfer(msg.sender, _amount);
    }

    function getCumulativeIssuanceFraction() external view returns (uint256) {
        return _getCumulativeIssuanceFraction();
    }

    function unprotectedIssueLQTY() external returns (uint256) {
        // No checks on caller address

        uint256 latestTotalLQTYIssued = LQTYSupplyCap * _getCumulativeIssuanceFraction() / DECIMAL_PRECISION;
        uint256 issuance = latestTotalLQTYIssued - totalLQTYIssued;

        totalLQTYIssued = latestTotalLQTYIssued;
        return issuance;
    }
}
