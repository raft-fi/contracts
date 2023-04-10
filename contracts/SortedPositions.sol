// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./Interfaces/IPositionManager.sol";
import "./PositionManagerDependent.sol";

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

/*
* A sorted doubly linked list with nodes sorted in descending order.
*
* Nodes map to active Positions in the system - the ID property is the address of a Position owner.
* Nodes are ordered according to their current nominal individual collateral ratio (NICR),
* which is like the ICR but without the price, i.e., just collateral / debt.
*
* The list optionally accepts insert position hints.
*
* NICRs are computed dynamically at runtime, and not stored on the Node. This is because NICRs of active Positions
* change dynamically as liquidation events occur.
*
* The list relies on the fact that liquidation events preserve ordering: a liquidation decreases the NICRs of all active Positions,
* but maintains their order. A node inserted based on current NICR will maintain the correct position,
* relative to it's peers, as rewards accumulate, as long as it's raw collateral and debt have not changed.
* Thus, Nodes remain sorted by current NICR.
*
* Nodes need only be re-inserted upon a Position operation - when the owner adds or removes collateral or debt
* to their position.
*
* The list is a modification of the following audited SortedDoublyLinkedList:
* https://github.com/livepeer/protocol/blob/master/contracts/libraries/SortedDoublyLL.sol
*
*
* Changes made in the Raft implementation:
*
* - Keys have been removed from nodes
*
* - Ordering checks for insertion are performed by comparing an NICR argument to the current NICR, calculated at runtime.
*   The list relies on the property that ordering by ICR is maintained as the collateralToken:USD price varies.
*/
library SortedPositions {
    event NodeAdded(address _id, uint256 _NICR);
    event NodeRemoved(address _id);

    // Information for a node in the list
    struct Node {
        bool exists;
        address nextId; // Id of next node (smaller NICR) in the list
        address prevId; // Id of previous node (larger NICR) in the list
    }

    // Information for the list
    struct Data {
        address first; // First element of the list. Also the node in the list with the largest NICR
        address last; // Last element of the list. Also the node in the list with the smallest NICR
        uint256 maxSize; // Maximum size of the list
        uint256 size; // Current size of the list
        mapping(address => Node) nodes; // Track the corresponding ids for each node in the list
    }

    /*
     * @dev Add a node to the list
     * @param _id Node's id
     * @param _NICR Node's NICR
     * @param _prevId Id of previous node for the insert position
     * @param _nextId Id of next node for the insert position
     */
    function insert(
        Data storage data,
        IPositionManager _positionManager,
        address _id,
        uint256 _NICR,
        address _prevId,
        address _nextId
    ) private {
        if (data.size == data.maxSize) {
            revert PositionsListFull();
        }
        if (data.nodes[_id].exists) {
            revert PositionsListContainsNode(_id);
        }
        if (_id == address(0)) {
            revert PositionIDZero();
        }
        if (_NICR == 0) {
            revert PositionsNICRZero();
        }

        address prevId = _prevId;
        address nextId = _nextId;

        if (!validInsertPosition(data, _positionManager, _NICR, prevId, nextId)) {
            // Sender's hint was not a valid insert position
            // Use sender's hint to find a valid insert position
            (prevId, nextId) = findInsertPosition(data, _positionManager, _NICR, prevId, nextId);
        }

        data.nodes[_id].exists = true;

        if (prevId == address(0) && nextId == address(0)) {
            // Insert as first and last
            data.first = _id;
            data.last = _id;
        } else if (prevId == address(0)) {
            // Insert before `prevId` as the first
            data.nodes[_id].nextId = data.first;
            data.nodes[data.first].prevId = _id;
            data.first = _id;
        } else if (nextId == address(0)) {
            // Insert after `nextId` as the last
            data.nodes[_id].prevId = data.last;
            data.nodes[data.last].nextId = _id;
            data.last = _id;
        } else {
            // Insert at insert position between `prevId` and `nextId`
            data.nodes[_id].nextId = nextId;
            data.nodes[_id].prevId = prevId;
            data.nodes[prevId].nextId = _id;
            data.nodes[nextId].prevId = _id;
        }

        ++data.size;
        emit NodeAdded(_id, _NICR);
    }

    /*
     * @dev Remove a node from the list
     * @param _id Node's id
     */
    function remove(Data storage data, address _id) internal {
        if (!data.nodes[_id].exists) {
            revert PositionsListDoesNotContainNode(_id);
        }

        if (data.size > 1) {
            // List contains more than a single node
            if (_id == data.first) {
                // The removed node is the first
                // Set first to next node
                data.first = data.nodes[_id].nextId;
                // Set prev pointer of new first to null
                data.nodes[data.first].prevId = address(0);
            } else if (_id == data.last) {
                // The removed node is the last
                // Set last to previous node
                data.last = data.nodes[_id].prevId;
                // Set next pointer of new last to null
                data.nodes[data.last].nextId = address(0);
            } else {
                // The removed node is neither the first nor the last
                // Set next pointer of previous node to the next node
                data.nodes[data.nodes[_id].prevId].nextId = data.nodes[_id].nextId;
                // Set prev pointer of next node to the previous node
                data.nodes[data.nodes[_id].nextId].prevId = data.nodes[_id].prevId;
            }
        } else {
            // List contains a single node
            // Set the first and last to null
            data.first = address(0);
            data.last = address(0);
        }

        delete data.nodes[_id];
        --data.size;
        emit NodeRemoved(_id);
    }

    /*
     * @dev Re-insert the node at a new position, based on its new NICR
     * @param _id Node's id
     * @param _newNICR Node's new NICR
     * @param _prevId Id of previous node for the new insert position
     * @param _nextId Id of next node for the new insert position
     */
    function update(
        Data storage data,
        IPositionManager _positionManager,
        address _id,
        uint256 _newNICR,
        address _prevId,
        address _nextId
    ) internal {
        if (_newNICR == 0) {
            revert PositionsNICRZero();
        }

        if (data.nodes[_id].exists) {
            // Remove node from the list
            remove(data, _id);
        }
        insert(data, _positionManager, _id, _newNICR, _prevId, _nextId);
    }

    /*
     * @dev Check if a pair of nodes is a valid insertion point for a new node with the given NICR
     * @param _NICR Node's NICR
     * @param _prevId Id of previous node for the insert position
     * @param _nextId Id of next node for the insert position
     */
    function validInsertPosition(
        Data storage data,
        IPositionManager _positionManager,
        uint256 _NICR,
        address _prevId,
        address _nextId
    ) private view returns (bool) {
        if (_prevId == address(0) && _nextId == address(0)) {
            // `(null, null)` is a valid insert position if the list is empty
            return data.size == 0;
        } else if (_prevId == address(0)) {
            // `(null, _nextId)` is a valid insert position if `_nextId` is the first of the list
            return data.first == _nextId && _NICR >= _positionManager.getNominalICR(_nextId);
        } else if (_nextId == address(0)) {
            // `(_prevId, null)` is a valid insert position if `_prevId` is the last of the list
            return data.last == _prevId && _NICR <= _positionManager.getNominalICR(_prevId);
        } else {
            // `(_prevId, _nextId)` is a valid insert position if they are adjacent nodes and `_NICR` falls between the two nodes' NICRs
            return data.nodes[_prevId].nextId == _nextId && _positionManager.getNominalICR(_prevId) >= _NICR
                && _NICR >= _positionManager.getNominalICR(_nextId);
        }
    }

    /*
     * @dev Descend the list (larger NICRs to smaller NICRs) to find a valid insert position
     * @param _positionManager PositionManager contract, passed in as param to save SLOAD’s
     * @param _NICR Node's NICR
     * @param _startId Id of node to start descending the list from
     */
    function _descendList(Data storage data, IPositionManager _positionManager, uint256 _NICR, address _startId)
        private
        view
        returns (address, address)
    {
        // If `_startId` is the first, check if the insert position is before the first
        if (data.first == _startId && _NICR >= _positionManager.getNominalICR(_startId)) {
            return (address(0), _startId);
        }

        address prevId = _startId;
        address nextId = data.nodes[prevId].nextId;

        // Descend the list until we reach the end or until we find a valid insert position
        while (prevId != address(0) && !validInsertPosition(data, _positionManager, _NICR, prevId, nextId)) {
            prevId = data.nodes[prevId].nextId;
            nextId = data.nodes[prevId].nextId;
        }

        return (prevId, nextId);
    }

    /*
     * @dev Ascend the list (smaller NICRs to larger NICRs) to find a valid insert position
     * @param _positionManager PositionManager contract, passed in as param to save SLOAD’s
     * @param _NICR Node's NICR
     * @param _startId Id of node to start ascending the list from
     */
    function _ascendList(Data storage data, IPositionManager _positionManager, uint256 _NICR, address _startId)
        private
        view
        returns (address, address)
    {
        // If `_startId` is the last, check if the insert position is after the last
        if (data.last == _startId && _NICR <= _positionManager.getNominalICR(_startId)) {
            return (_startId, address(0));
        }

        address nextId = _startId;
        address prevId = data.nodes[nextId].prevId;

        // Ascend the list until we reach the end or until we find a valid insertion point
        while (nextId != address(0) && !validInsertPosition(data, _positionManager, _NICR, prevId, nextId)) {
            nextId = data.nodes[nextId].prevId;
            prevId = data.nodes[nextId].prevId;
        }

        return (prevId, nextId);
    }

    /*
     * @dev Find the insert position for a new node with the given NICR
     * @param _NICR Node's NICR
     * @param _prevId Id of previous node for the insert position
     * @param _nextId Id of next node for the insert position
     */
    function findInsertPosition(
        Data storage data,
        IPositionManager _positionManager,
        uint256 _NICR,
        address _prevId,
        address _nextId
    ) private view returns (address, address) {
        address prevId = _prevId;
        address nextId = _nextId;

        if (prevId != address(0)) {
            if (!data.nodes[prevId].exists || _NICR > _positionManager.getNominalICR(prevId)) {
                // `prevId` does not exist anymore or now has a smaller NICR than the given NICR
                prevId = address(0);
            }
        }

        if (nextId != address(0)) {
            if (!data.nodes[nextId].exists || _NICR < _positionManager.getNominalICR(nextId)) {
                // `nextId` does not exist anymore or now has a larger NICR than the given NICR
                nextId = address(0);
            }
        }

        if (prevId == address(0) && nextId == address(0)) {
            // No hint - descend list starting from first
            return _descendList(data, _positionManager, _NICR, data.first);
        } else if (prevId == address(0)) {
            // No `prevId` for hint - ascend list starting from `nextId`
            return _ascendList(data, _positionManager, _NICR, nextId);
        } else if (nextId == address(0)) {
            // No `nextId` for hint - descend list starting from `prevId`
            return _descendList(data, _positionManager, _NICR, prevId);
        } else {
            // Descend list starting from `prevId`
            return _descendList(data, _positionManager, _NICR, prevId);
        }
    }
}
