// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import './IActivePool.sol';
import './IDefaultPool.sol';
import "./IPriceFeed.sol";


interface ILiquityBase {
    function activePool() external view returns (IActivePool);
    
    function defaultPool() external view returns (IDefaultPool);

    function priceFeed() external view returns (IPriceFeed);
}
