// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

/// @dev Helper interface for Chai token.
interface IChai {
    function join(address dst, uint256 wad) external;
    function draw(address src, uint256 wad) external;
    function transfer(address dst, uint256 wad) external returns (bool);
}
