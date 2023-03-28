// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../../contracts/Interfaces/ISortedPositions.sol";


contract SortedPositionsTester {
    ISortedPositions sortedPositions;

    function setSortedPositions(address _sortedPositionsAddress) external {
        sortedPositions = ISortedPositions(_sortedPositionsAddress);
    }

    function insert(address _id, uint256 _NICR, address _prevId, address _nextId) external {
        sortedPositions.insert(_id, _NICR, _prevId, _nextId);
    }

    function remove(address _id) external {
        sortedPositions.remove(_id);
    }

    function reInsert(address _id, uint256 _newNICR, address _prevId, address _nextId) external {
        sortedPositions.reInsert(_id, _newNICR, _prevId, _nextId);
    }

    function getNominalICR(address) external pure returns (uint) {
        return 1;
    }

    function getCurrentICR(address, uint) external pure returns (uint) {
        return 1;
    }
}
