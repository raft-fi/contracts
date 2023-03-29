// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;
pragma experimental ABIEncoderV2;

import "./PositionManager.sol";
import "./SortedPositions.sol";

/*  Helper contract for grabbing Position data for the front end. Not part of the core Liquity system. */
contract MultiPositionGetter {
    struct CombinedPositionData {
        address owner;

        uint debt;
        uint coll;
        uint stake;

        uint snapshotCollateralBalance;
        uint snapshotRDebt;
    }

    PositionManager public positionManager; // XXX Positions missing from IPositionManager?
    ISortedPositions public sortedPositions;

    constructor(PositionManager _positionManager, ISortedPositions _sortedPositions) {
        positionManager = _positionManager;
        sortedPositions = _sortedPositions;
    }

    function getMultipleSortedPositions(int _startIdx, uint _count)
        external view returns (CombinedPositionData[] memory _positions)
    {
        uint startIdx;
        bool descend;

        if (_startIdx >= 0) {
            startIdx = uint(_startIdx);
            descend = true;
        } else {
            startIdx = uint(-(_startIdx + 1));
            descend = false;
        }

        uint sortedPositionsSize = sortedPositions.getSize();

        if (startIdx >= sortedPositionsSize) {
            _positions = new CombinedPositionData[](0);
        } else {
            uint maxCount = sortedPositionsSize - startIdx;

            if (_count > maxCount) {
                _count = maxCount;
            }

            if (descend) {
                _positions = _getMultipleSortedPositionsFromHead(startIdx, _count);
            } else {
                _positions = _getMultipleSortedPositionsFromTail(startIdx, _count);
            }
        }
    }

    function _getMultipleSortedPositionsFromHead(uint _startIdx, uint _count)
        internal view returns (CombinedPositionData[] memory _positions)
    {
        address currentPositionowner = sortedPositions.getFirst();

        for (uint idx = 0; idx < _startIdx; ++idx) {
            currentPositionowner = sortedPositions.getNext(currentPositionowner);
        }

        _positions = new CombinedPositionData[](_count);

        for (uint idx = 0; idx < _count; ++idx) {
            _positions[idx].owner = currentPositionowner;
            (
                _positions[idx].debt,
                _positions[idx].coll,
                _positions[idx].stake,
                /* status */,
                /* arrayIndex */
            ) = positionManager.positions(currentPositionowner);
            (
                _positions[idx].snapshotCollateralBalance,
                _positions[idx].snapshotRDebt
            ) = positionManager.rewardSnapshots(currentPositionowner);

            currentPositionowner = sortedPositions.getNext(currentPositionowner);
        }
    }

    function _getMultipleSortedPositionsFromTail(uint _startIdx, uint _count)
        internal view returns (CombinedPositionData[] memory _positions)
    {
        address currentPositionowner = sortedPositions.getLast();

        for (uint idx = 0; idx < _startIdx; ++idx) {
            currentPositionowner = sortedPositions.getPrev(currentPositionowner);
        }

        _positions = new CombinedPositionData[](_count);

        for (uint idx = 0; idx < _count; ++idx) {
            _positions[idx].owner = currentPositionowner;
            (
                _positions[idx].debt,
                _positions[idx].coll,
                _positions[idx].stake,
                /* status */,
                /* arrayIndex */
            ) = positionManager.positions(currentPositionowner);
            (
                _positions[idx].snapshotCollateralBalance,
                _positions[idx].snapshotRDebt
            ) = positionManager.rewardSnapshots(currentPositionowner);

            currentPositionowner = sortedPositions.getPrev(currentPositionowner);
        }
    }
}
