// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../../contracts/LQTY/CommunityIssuance.sol";

contract CommunityIssuanceTester is CommunityIssuance {
    function obtainLQTY(uint _amount) external {
        lqtyToken.transfer(msg.sender, _amount);
    }

    function getCumulativeIssuanceFraction() external view returns (uint) {
       return _getCumulativeIssuanceFraction();
    }

    function unprotectedIssueLQTY() external returns (uint) {
        // No checks on caller address

        uint latestTotalLQTYIssued = LQTYSupplyCap * _getCumulativeIssuanceFraction() / DECIMAL_PRECISION;
        uint issuance = latestTotalLQTYIssued - totalLQTYIssued;

        totalLQTYIssued = latestTotalLQTYIssued;
        return issuance;
    }
}
