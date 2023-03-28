// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IPositionManager.sol";

/// @dev Caller is neither Borrower Operations nor Position Manager.
error SortedPositionsInvalidCaller();

/// @dev Positions list size cannot be zero.
error PositionsSizeZero();

/// @dev Positions list is full.
error PositionsListFull();

/// @dev Positions list already contains the node.
error PositionsListContainsNode(address id);

/// @dev Positions list does not contain the node.
error PositionsListDoesNotContainNode(address id);

/// @dev Position ID cannot be zero.
error PositionIDZero();

/// @dev Positions' NICR must is zero.
error PositionsNICRZero();

// Common interface for the SortedPositions Doubly Linked List.
interface ISortedPositions {

    // --- Events ---

    event SortedPositionsAddressChanged(address _sortedDoublyLLAddress);
    event NodeAdded(address _id, uint _NICR);
    event NodeRemoved(address _id);

    // --- Functions ---

    function setParams(uint256 _size, IPositionManager _positionManager) external;

    function insert(address _id, uint256 _ICR, address _prevId, address _nextId) external;

    function remove(address _id) external;

    function reInsert(address _id, uint256 _newICR, address _prevId, address _nextId) external;

    function contains(address _id) external view returns (bool);

    function isFull() external view returns (bool);

    function isEmpty() external view returns (bool);

    function getSize() external view returns (uint256);

    function getMaxSize() external view returns (uint256);

    function getFirst() external view returns (address);

    function getLast() external view returns (address);

    function getNext(address _id) external view returns (address);

    function getPrev(address _id) external view returns (address);

    function validInsertPosition(uint256 _ICR, address _prevId, address _nextId) external view returns (bool);

    function findInsertPosition(uint256 _ICR, address _prevId, address _nextId) external view returns (address, address);
}
