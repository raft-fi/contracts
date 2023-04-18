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
    // --- Types ---

    /// @dev Information for a node in the list.
    /// @param exists Whether the node exists in the list.
    /// @param nextID The ID of next node (smaller NICR) in the list.
    /// @param previousID The ID of previous node (larger NICR) in the list.
    struct Node {
        bool exists;
        address nextID;
        address previousID;
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

    // --- Events ---

    /// @dev Emitted when a node is added to the list.
    /// @param id The ID of the node.
    /// @param nicr The NICR of the position.
    event NodeAdded(address id, uint256 nicr);

    /// @dev Emitted when a node is removed from the list.
    /// @param id The ID of the node.
    event NodeRemoved(address id);

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

    // --- Functions ---

    /// @dev Removes the node with the given ID from the list.
    /// @param list The list.
    /// @param id The ID of the node to remove.
    function _remove(Data storage list, address id) internal {
        if (!list.nodes[id].exists) {
            revert DoesNotContainPosition(id);
        }

        if (list.size > 1) {
            // List contains more than a single node
            if (id == list.first) {
                // The removed node is the first
                // Set first to next node
                list.first = list.nodes[id].nextID;
                // Set prev pointer of new first to null
                list.nodes[list.first].previousID = address(0);
            } else if (id == list.last) {
                // The removed node is the last
                // Set last to previous node
                list.last = list.nodes[id].previousID;
                // Set next pointer of new last to null
                list.nodes[list.last].nextID = address(0);
            } else {
                // The removed node is neither the first nor the last
                // Set next pointer of previous node to the next node
                list.nodes[list.nodes[id].previousID].nextID = list.nodes[id].nextID;
                // Set prev pointer of next node to the previous node
                list.nodes[list.nodes[id].nextID].previousID = list.nodes[id].previousID;
            }
        } else {
            // List contains a single node
            // Set the first and last to null
            list.first = address(0);
            list.last = address(0);
        }

        delete list.nodes[id];
        --list.size;
        emit NodeRemoved(id);
    }

    /// @dev Updates the node at a new position, based on its new NICR.
    /// @param list The list.
    /// @param positionManager The position manager.
    /// @param collateralToken The collateral token.
    /// @param id The ID of the node to update.
    /// @param newNICR New ICR of the position.
    /// @param previousID The ID of the previous node for the new insert position.
    /// @param nextID The ID of the next node for the new insert position.
    function _update(
        Data storage list,
        IPositionManager positionManager,
        IERC20 collateralToken,
        address id,
        uint256 newNICR,
        address previousID,
        address nextID
    ) internal {
        if (newNICR == 0) {
            revert NICRIsZero();
        }

        if (list.nodes[id].exists) {
            _remove(list, id);
        }

        _insert(list, positionManager, collateralToken, id, newNICR, previousID, nextID);
    }

    /// @dev Adds a node to the list.
    /// @param list The list.
    /// @param positionManager The position manager.
    /// @param collateralToken The collateral token.
    /// @param id The ID of the node to insert.
    /// @param nicr The NICR of the position.
    /// @param previousID The ID of previous node for the insert position.
    /// @param nextID The ID of next node for the insert position.
    // solhint-disable-next-line code-complexity
    function _insert(
        Data storage list,
        IPositionManager positionManager,
        IERC20 collateralToken,
        address id,
        uint256 nicr,
        address previousID,
        address nextID
    ) private {
        if (list.size == list.maxSize) {
            revert ListIsFull();
        }
        if (list.nodes[id].exists) {
            revert AlreadyContainsPosition(id);
        }
        if (id == address(0)) {
            revert PositionIDZero();
        }
        if (nicr == 0) {
            revert NICRIsZero();
        }

        if (!_isValidInsertPosition(list, positionManager, collateralToken, nicr, previousID, nextID)) {
            // Sender's hint was not a valid insert position
            // Use sender's hint to find a valid insert position
            (previousID, nextID) =
                _findInsertPosition(list, positionManager, collateralToken, nicr, previousID, nextID);
        }

        list.nodes[id].exists = true;

        if (previousID == address(0) && nextID == address(0)) {
            // Insert as first and last
            list.first = id;
            list.last = id;
        } else if (previousID == address(0)) {
            // Insert before `previousID` as the first
            list.nodes[id].nextID = list.first;
            list.nodes[list.first].previousID = id;
            list.first = id;
        } else if (nextID == address(0)) {
            // Insert after `nextID` as the last
            list.nodes[id].previousID = list.last;
            list.nodes[list.last].nextID = id;
            list.last = id;
        } else {
            // Insert at insert position between `previousID` and `nextID`
            list.nodes[id].nextID = nextID;
            list.nodes[id].previousID = previousID;
            list.nodes[previousID].nextID = id;
            list.nodes[nextID].previousID = id;
        }

        ++list.size;
        emit NodeAdded(id, nicr);
    }

    /// @dev Checks whether a pair of nodes is a valid insertion point for a new node with the given NICR.
    /// @param list The list.
    /// @param positionManager The position manager.
    /// @param collateralToken The collateral token.
    /// @param nicr The NICR of the position.
    /// @param previousID The ID of the previous node for the insert position.
    /// @param nextID The ID of the next node for the insert position.
    /// @return True if the pair of nodes is a valid insertion point for a new node with the given NICR.
    function _isValidInsertPosition(
        Data storage list,
        IPositionManager positionManager,
        IERC20 collateralToken,
        uint256 nicr,
        address previousID,
        address nextID
    ) private view returns (bool) {
        // `(null, null)` is a valid insert position if the list is empty
        if (previousID == address(0) && nextID == address(0)) {
            return list.size == 0;
        }

        // `(null, nextID)` is a valid insert position if `nextID` is the first of the list
        if (previousID == address(0)) {
            return list.first == nextID && nicr >= positionManager.getNominalICR(collateralToken, nextID);
        }

        // `(previousID, null)` is a valid insert position if `previousID` is the last of the list
        if (nextID == address(0)) {
            return list.last == previousID && nicr <= positionManager.getNominalICR(collateralToken, previousID);
        }

        // `(previousID, nextID)` is a valid insert position if they are adjacent nodes and `nicr` falls between the
        // two nodes' NICRs
        return list.nodes[previousID].nextID == nextID
            && positionManager.getNominalICR(collateralToken, previousID) >= nicr
            && nicr >= positionManager.getNominalICR(collateralToken, nextID);
    }

    /// @dev Descends the list (larger NICRs to smaller NICRs) to find a valid insert position.
    /// @param data The list.
    /// @param positionManager The position manager.
    /// @param collateralToken The collateral token.
    /// @param nicr The NICR of the position.
    /// @param startId The ID of a node to start descending the list from.
    /// @return The IDs of the previous and next nodes for the insert position.
    function _descendList(
        Data storage data,
        IPositionManager positionManager,
        IERC20 collateralToken,
        uint256 nicr,
        address startId
    ) private view returns (address, address) {
        // If `startId` is the first, check if the insert position is before the first
        if (data.first == startId && nicr >= positionManager.getNominalICR(collateralToken, startId)) {
            return (address(0), startId);
        }

        address previousID = startId;
        address nextID = data.nodes[previousID].nextID;

        // Descend the list until we reach the end or until we find a valid insert position
        while (
            previousID != address(0)
                && !_isValidInsertPosition(data, positionManager, collateralToken, nicr, previousID, nextID)
        ) {
            previousID = data.nodes[previousID].nextID;
            nextID = data.nodes[previousID].nextID;
        }

        return (previousID, nextID);
    }

    /// @dev Ascends the list (smaller NICRs to larger NICRs) to find a valid insert position.
    /// @param data The list.
    /// @param positionManager The position manager.
    /// @param collateralToken The collateral token.
    /// @param nicr The NICR of the position.
    /// @param startId The ID of a node to start ascending the list from.
    /// @return The IDs of the previous and next nodes for the insert position.
    function _ascendList(
        Data storage data,
        IPositionManager positionManager,
        IERC20 collateralToken,
        uint256 nicr,
        address startId
    ) private view returns (address, address) {
        // If `startId` is the last, check if the insert position is after the last
        if (data.last == startId && nicr <= positionManager.getNominalICR(collateralToken, startId)) {
            return (startId, address(0));
        }

        address nextID = startId;
        address previousID = data.nodes[nextID].previousID;

        // Ascend the list until we reach the end or until we find a valid insertion point
        while (
            nextID != address(0)
                && !_isValidInsertPosition(data, positionManager, collateralToken, nicr, previousID, nextID)
        ) {
            nextID = data.nodes[nextID].previousID;
            previousID = data.nodes[nextID].previousID;
        }

        return (previousID, nextID);
    }

    /// @dev Finds the insert position for a new node with the given NICR.
    /// @param data The list.
    /// @param positionManager The position manager.
    /// @param collateralToken The collateral token.
    /// @param nicr The NICR of the position.
    /// @param previousID The ID of the previous node for the insert position.
    /// @param nextID The ID of the next node for the insert position.
    /// @return The IDs of the previous and next nodes for the insert position.
    function _findInsertPosition(
        Data storage data,
        IPositionManager positionManager,
        IERC20 collateralToken,
        uint256 nicr,
        address previousID,
        address nextID
    ) private view returns (address, address) {
        // `previousID` does not exist anymore or now has a smaller NICR than the given NICR
        if (
            previousID != address(0)
                && (!data.nodes[previousID].exists || nicr > positionManager.getNominalICR(collateralToken, previousID))
        ) {
            previousID = address(0);
        }

        // `nextID` does not exist anymore or now has a larger NICR than the given NICR
        if (
            nextID != address(0)
                && (!data.nodes[nextID].exists || nicr < positionManager.getNominalICR(collateralToken, nextID))
        ) {
            nextID = address(0);
        }

        // No hint - descend list starting from first
        if (previousID == address(0) && nextID == address(0)) {
            return _descendList(data, positionManager, collateralToken, nicr, data.first);
        }

        // No `previousID` for hint - ascend list starting from `nextID`
        if (previousID == address(0)) {
            return _ascendList(data, positionManager, collateralToken, nicr, nextID);
        }

        // No `nextID` for hint - descend list starting from `previousID`
        if (nextID == address(0)) {
            return _descendList(data, positionManager, collateralToken, nicr, previousID);
        }

        // Descend list starting from `previousID`
        return _descendList(data, positionManager, collateralToken, nicr, previousID);
    }
}
