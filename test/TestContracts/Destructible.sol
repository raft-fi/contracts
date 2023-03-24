// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

contract Destructible {
    function destruct(address payable _receiver) external {
        selfdestruct(_receiver);
    }
}
