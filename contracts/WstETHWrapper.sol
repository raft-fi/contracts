// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IStETH } from "./Dependencies/IStETH.sol";
import { IWstETH } from "./Dependencies/IWstETH.sol";
import { IWstETHWrapper } from "./Interfaces/IWstETHWrapper.sol";

abstract contract WstETHWrapper is IWstETHWrapper {
    IWstETH public immutable override wstETH;
    IStETH public immutable override stETH;

    constructor(IWstETH wstETH_) {
        if (address(wstETH_) == address(0)) {
            revert WstETHAddressCannotBeZero();
        }
        wstETH = wstETH_;
        stETH = IStETH(address(wstETH_.stETH()));

        stETH.approve(address(wstETH), type(uint256).max); // for wrapping
    }

    function wrapStETH(uint256 stETHAmount) internal returns (uint256) {
        stETH.transferFrom(msg.sender, address(this), stETHAmount);
        return wstETH.wrap(stETHAmount);
    }

    function unwrapStETH(uint256 wstETHAmount) internal {
        stETH.transfer(msg.sender, wstETH.unwrap(wstETHAmount));
    }
}
