// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IWrappedCollateralToken } from "./IWrappedCollateralToken.sol";

interface IERC20WrappedLockable is IWrappedCollateralToken {
    function setLock(bool lock) external;
    function isLocked() external view returns (bool);
}
