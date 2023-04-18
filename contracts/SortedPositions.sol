// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManager} from "./Interfaces/IPositionManager.sol";
import {PositionManagerDependent} from "./PositionManagerDependent.sol";

/// @dev A sorted doubly linked list with nodes sorted in descending order.
///
/// Nodes map to active positions in the system - the ID property is the address of a position owner.
/// Nodes are ordered according to their current nominal individual collateral ratio (NICR),
/// which is like the ICR but without the price, i.e., just collateral / debt.
///
/// The list optionally accepts insert position hints.
///
/// NICRs are computed dynamically at runtime, and not stored in the node. This is because NICRs of active positions
/// change dynamically as liquidation events occur.
///
/// The list relies on the fact that liquidation events preserve ordering: a liquidation decreases the NICRs of all
/// active positions, but maintains their order. A node inserted based on current NICR will maintain the correct
/// position, relative to it's peers, as rewards accumulate, as long as it's raw collateral and debt have not changed.
/// Thus, nodes remain sorted by current NICR.
///
/// Nodes need only be updated upon a position operation - when the owner adds or removes collateral or debt to their
/// position.
///
/// The list is a modification of the following audited `SortedDoublyLinkedList`:
/// https://github.com/livepeer/protocol/blob/master/contracts/libraries/SortedDoublyLL.sol
///
/// Changes made in the Raft implementation:
/// - Keys have been removed from nodes
/// - Ordering checks for insertion are performed by comparing an NICR argument to the current NICR, calculated at
///   runtime. The list relies on the property that ordering by ICR is maintained as the collateralToken:USD price
///   varies.
library SortedPositions {
    // --- Errors ---

    /// @dev Positions list size cannot be zero.
    error SizeCannotBeZero();

    /// @dev Positions list is full.
    error ListIsFull();

    /// @dev Positions list already contains the node.
    /// @param id The ID of the node.
    error AlreadyContainsPosition(address id);

    /// @dev Positions list does not contain the node.
    /// @param id The ID of the node.
    error DoesNotContainPosition(address id);

    /// @dev Position ID cannot be zero.
    error PositionIDZero();

    /// @dev Position's NICR is zero.
    error NICRIsZero();

    // --- Events ---

    /// @dev Emitted when a node is added to the list.
    /// @param _id The ID of the node.
    /// @param nicr The NICR of the position.
    event NodeAdded(address _id, uint256 nicr);

    /// @dev Emitted when a node is removed from the list.
    /// @param _id The ID of the node.
    event NodeRemoved(address _id);

    /// @dev Information for a node in the list.
    /// @param exists Whether the node exists in the list.
    /// @param nextId The ID of next node (smaller NICR) in the list.
    /// @param prevId The ID of previous node (larger NICR) in the list.
    struct Node {
        bool exists;
        address nextId;
        address prevId;
    }

    /// @dev Information for the sorted position list.
    /// @param first The first element of the list (largest NICR).
    /// @param last The last element of the list (smallest NICR).
    /// @param maxSize The maximum size of the list.
    /// @param size The current size of the list.
    /// @param nodes The nodes in the list.
    struct Data {
        address first;
        address last;
        uint256 maxSize;
        uint256 size;
        mapping(address => Node) nodes;
    }

    /// @dev Adds a node to the list.
    /// @param list The list.
    /// @param _positionManager The position manager.
    /// @param _collateralToken The collateral token.
    /// @param _id The ID of the node to insert.
    /// @param nicr The NICR of the position.
    /// @param _prevId The ID of previous node for the insert position.
    /// @param _nextId The ID of next node for the insert position.
    // solhint-disable-next-line code-complexity
    function insert(
        Data storage list,
        IPositionManager _positionManager,
        IERC20 _collateralToken,
        address _id,
        uint256 nicr,
        address _prevId,
        address _nextId
    ) private {
        if (list.size == list.maxSize) {
            revert ListIsFull();
        }
        if (list.nodes[_id].exists) {
            revert AlreadyContainsPosition(_id);
        }
        if (_id == address(0)) {
            revert PositionIDZero();
        }
        if (nicr == 0) {
            revert NICRIsZero();
        }

        address prevId = _prevId;
        address nextId = _nextId;

        if (!validInsertPosition(list, _positionManager, _collateralToken, nicr, prevId, nextId)) {
            // Sender's hint was not a valid insert position
            // Use sender's hint to find a valid insert position
            (prevId, nextId) = findInsertPosition(list, _positionManager, _collateralToken, nicr, prevId, nextId);
        }

        list.nodes[_id].exists = true;

        if (prevId == address(0) && nextId == address(0)) {
            // Insert as first and last
            list.first = _id;
            list.last = _id;
        } else if (prevId == address(0)) {
            // Insert before `prevId` as the first
            list.nodes[_id].nextId = list.first;
            list.nodes[list.first].prevId = _id;
            list.first = _id;
        } else if (nextId == address(0)) {
            // Insert after `nextId` as the last
            list.nodes[_id].prevId = list.last;
            list.nodes[list.last].nextId = _id;
            list.last = _id;
        } else {
            // Insert at insert position between `prevId` and `nextId`
            list.nodes[_id].nextId = nextId;
            list.nodes[_id].prevId = prevId;
            list.nodes[prevId].nextId = _id;
            list.nodes[nextId].prevId = _id;
        }

        ++list.size;
        emit NodeAdded(_id, nicr);
    }

    /// @dev Removes the node with the given ID from the list.
    /// @param list The list.
    /// @param _id The ID of the node to remove.
    function remove(Data storage list, address _id) internal {
        if (!list.nodes[_id].exists) {
            revert DoesNotContainPosition(_id);
        }

        if (list.size > 1) {
            // List contains more than a single node
            if (_id == list.first) {
                // The removed node is the first
                // Set first to next node
                list.first = list.nodes[_id].nextId;
                // Set prev pointer of new first to null
                list.nodes[list.first].prevId = address(0);
            } else if (_id == list.last) {
                // The removed node is the last
                // Set last to previous node
                list.last = list.nodes[_id].prevId;
                // Set next pointer of new last to null
                list.nodes[list.last].nextId = address(0);
            } else {
                // The removed node is neither the first nor the last
                // Set next pointer of previous node to the next node
                list.nodes[list.nodes[_id].prevId].nextId = list.nodes[_id].nextId;
                // Set prev pointer of next node to the previous node
                list.nodes[list.nodes[_id].nextId].prevId = list.nodes[_id].prevId;
            }
        } else {
            // List contains a single node
            // Set the first and last to null
            list.first = address(0);
            list.last = address(0);
        }

        delete list.nodes[_id];
        --list.size;
        emit NodeRemoved(_id);
    }

    /// @dev Updates the node at a new position, based on its new NICR.
    /// @param list The list.
    /// @param _positionManager The position manager.
    /// @param _collateralToken The collateral token.
    /// @param _id The ID of the node to update.
    /// @param _newNICR New ICR of the position.
    /// @param _prevId The ID of the previous node for the new insert position.
    /// @param _nextId The ID of the next node for the new insert position.
    function update(
        Data storage list,
        IPositionManager _positionManager,
        IERC20 _collateralToken,
        address _id,
        uint256 _newNICR,
        address _prevId,
        address _nextId
    ) internal {
        if (_newNICR == 0) {
            revert NICRIsZero();
        }

        if (list.nodes[_id].exists) {
            // Remove node from the list
            remove(list, _id);
        }

        insert(list, _positionManager, _collateralToken, _id, _newNICR, _prevId, _nextId);
    }

    /// @dev Checks whether a pair of nodes is a valid insertion point for a new node with the given NICR.
    /// @param list The list.
    /// @param _positionManager The position manager.
    /// @param _collateralToken The collateral token.
    /// @param nicr The NICR of the position.
    /// @param _prevId The ID of the previous node for the insert position.
    /// @param _nextId The ID of the next node for the insert position.
    /// @return True if the pair of nodes is a valid insertion point for a new node with the given NICR.
    function validInsertPosition(
        Data storage list,
        IPositionManager _positionManager,
        IERC20 _collateralToken,
        uint256 nicr,
        address _prevId,
        address _nextId
    ) private view returns (bool) {
        // `(null, null)` is a valid insert position if the list is empty
        if (_prevId == address(0) && _nextId == address(0)) {
            return list.size == 0;
        }

        // `(null, _nextId)` is a valid insert position if `_nextId` is the first of the list
        if (_prevId == address(0)) {
            return list.first == _nextId && nicr >= _positionManager.getNominalICR(_collateralToken, _nextId);
        }

        // `(_prevId, null)` is a valid insert position if `_prevId` is the last of the list
        if (_nextId == address(0)) {
            return list.last == _prevId && nicr <= _positionManager.getNominalICR(_collateralToken, _prevId);
        }

        // `(_prevId, _nextId)` is a valid insert position if they are adjacent nodes and `nicr` falls between the
        // two nodes' NICRs
        return list.nodes[_prevId].nextId == _nextId
            && _positionManager.getNominalICR(_collateralToken, _prevId) >= nicr
            && nicr >= _positionManager.getNominalICR(_collateralToken, _nextId);
    }

    /// @dev Descends the list (larger NICRs to smaller NICRs) to find a valid insert position.
    /// @param data The list.
    /// @param _positionManager The position manager.
    /// @param _collateralToken The collateral token.
    /// @param nicr The NICR of the position.
    /// @param _startId The ID of a node to start descending the list from.
    /// @return The IDs of the previous and next nodes for the insert position.
    function _descendList(
        Data storage data,
        IPositionManager _positionManager,
        IERC20 _collateralToken,
        uint256 nicr,
        address _startId
    ) private view returns (address, address) {
        // If `_startId` is the first, check if the insert position is before the first
        if (data.first == _startId && nicr >= _positionManager.getNominalICR(_collateralToken, _startId)) {
            return (address(0), _startId);
        }

        address prevId = _startId;
        address nextId = data.nodes[prevId].nextId;

        // Descend the list until we reach the end or until we find a valid insert position
        while (
            prevId != address(0) && !validInsertPosition(data, _positionManager, _collateralToken, nicr, prevId, nextId)
        ) {
            prevId = data.nodes[prevId].nextId;
            nextId = data.nodes[prevId].nextId;
        }

        return (prevId, nextId);
    }

    /// @dev Ascends the list (smaller NICRs to larger NICRs) to find a valid insert position.
    /// @param data The list.
    /// @param _positionManager The position manager.
    /// @param _collateralToken The collateral token.
    /// @param nicr The NICR of the position.
    /// @param _startId The ID of a node to start ascending the list from.
    /// @return The IDs of the previous and next nodes for the insert position.
    function _ascendList(
        Data storage data,
        IPositionManager _positionManager,
        IERC20 _collateralToken,
        uint256 nicr,
        address _startId
    ) private view returns (address, address) {
        // If `_startId` is the last, check if the insert position is after the last
        if (data.last == _startId && nicr <= _positionManager.getNominalICR(_collateralToken, _startId)) {
            return (_startId, address(0));
        }

        address nextId = _startId;
        address prevId = data.nodes[nextId].prevId;

        // Ascend the list until we reach the end or until we find a valid insertion point
        while (
            nextId != address(0) && !validInsertPosition(data, _positionManager, _collateralToken, nicr, prevId, nextId)
        ) {
            nextId = data.nodes[nextId].prevId;
            prevId = data.nodes[nextId].prevId;
        }

        return (prevId, nextId);
    }

    /// @dev Finds the insert position for a new node with the given NICR.
    /// @param data The list.
    /// @param _positionManager The position manager.
    /// @param _collateralToken The collateral token.
    /// @param nicr The NICR of the position.
    /// @param _prevId The ID of the previous node for the insert position.
    /// @param _nextId The ID of the next node for the insert position.
    /// @return The IDs of the previous and next nodes for the insert position.
    function findInsertPosition(
        Data storage data,
        IPositionManager _positionManager,
        IERC20 _collateralToken,
        uint256 nicr,
        address _prevId,
        address _nextId
    ) private view returns (address, address) {
        address prevId = _prevId;
        address nextId = _nextId;

        // `prevId` does not exist anymore or now has a smaller NICR than the given NICR
        if (
            prevId != address(0)
                && (!data.nodes[prevId].exists || nicr > _positionManager.getNominalICR(_collateralToken, prevId))
        ) {
            prevId = address(0);
        }

        // `nextId` does not exist anymore or now has a larger NICR than the given NICR
        if (
            nextId != address(0)
                && (!data.nodes[nextId].exists || nicr < _positionManager.getNominalICR(_collateralToken, nextId))
        ) {
            nextId = address(0);
        }

        // No hint - descend list starting from first
        if (prevId == address(0) && nextId == address(0)) {
            return _descendList(data, _positionManager, _collateralToken, nicr, data.first);
        }

        // No `prevId` for hint - ascend list starting from `nextId`
        if (prevId == address(0)) {
            return _ascendList(data, _positionManager, _collateralToken, nicr, nextId);
        }

        // No `nextId` for hint - descend list starting from `prevId`
        if (nextId == address(0)) {
            return _descendList(data, _positionManager, _collateralToken, nicr, prevId);
        }

        // Descend list starting from `prevId`
        return _descendList(data, _positionManager, _collateralToken, nicr, prevId);
    }
}
