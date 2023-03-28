// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import '../../contracts/Interfaces/IPositionManager.sol';
import '../../contracts/Interfaces/ISortedPositions.sol';
import '../../contracts/Interfaces/IPriceFeed.sol';
import '../../contracts/Dependencies/LiquityMath.sol';

/* Wrapper contract - used for calculating gas of read-only and internal functions.
Not part of the Liquity application. */
contract FunctionCaller {

    IPositionManager positionManager;
    address public positionManagerAddress;

    ISortedPositions sortedPositions;
    address public sortedPositionsAddress;

    IPriceFeed priceFeed;
    address public priceFeedAddress;

    // --- Dependency setters ---

    function setPositionManagerAddress(address _positionManagerAddress) external {
        positionManagerAddress = _positionManagerAddress;
        positionManager = IPositionManager(_positionManagerAddress);
    }

    function setSortedPositionsAddress(address _sortedPositionsAddress) external {
        positionManagerAddress = _sortedPositionsAddress;
        sortedPositions = ISortedPositions(_sortedPositionsAddress);
    }

     function setPriceFeedAddress(address _priceFeedAddress) external {
        priceFeedAddress = _priceFeedAddress;
        priceFeed = IPriceFeed(_priceFeedAddress);
    }

    // --- Non-view wrapper functions used for calculating gas ---

    function positionManager_getCurrentICR(address _address, uint _price) external returns (uint) {
        return positionManager.getCurrentICR(_address, _price);
    }

    function sortedPositions_findInsertPosition(uint _NICR, address _prevId, address _nextId) external returns (address, address) {
        return sortedPositions.findInsertPosition(_NICR, _prevId, _nextId);
    }
}
