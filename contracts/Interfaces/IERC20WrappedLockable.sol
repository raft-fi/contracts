// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20Wrapped } from "./IERC20Wrapped.sol";

interface IERC20WrappedLockable is IERC20Wrapped {
    function unlock() external;
    function lock() external;
    function isLocked() external view returns (bool);
}
