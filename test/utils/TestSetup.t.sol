// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";
import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IPositionManager } from "../../contracts/Interfaces/IPositionManager.sol";
import { IPriceFeed } from "../../contracts/Interfaces/IPriceFeed.sol";
import { ISplitLiquidationCollateral } from "../../contracts/Interfaces/ISplitLiquidationCollateral.sol";
import { SplitLiquidationCollateral } from "../../contracts/SplitLiquidationCollateral.sol";
import { WstETHTokenMock } from "../mocks/WstETHTokenMock.sol";

contract TestSetup is Test {
    // User accounts
    address public constant ALICE = address(1);
    address public constant BOB = address(2);
    address public constant CAROL = address(3);
    address public constant DAVE = address(4);
    address public constant EVE = address(5);
    address public constant FRANK = address(6);

    // Fee recipients
    address public constant FEE_RECIPIENT = address(100);
    address public constant NEW_FEE_RECIPIENT = address(101);

    // Mocked contract addresses
    IPriceFeed public constant PRICE_FEED = IPriceFeed(address(12_345));
    IPositionManager public constant POSITION_MANAGER = IPositionManager(address(34_567));

    // Collateral token mock
    WstETHTokenMock public collateralToken;
    ISplitLiquidationCollateral public splitLiquidationCollateral;

    ERC20PermitSignature public emptySignature;

    function setUp() public virtual {
        collateralToken = new WstETHTokenMock();
        splitLiquidationCollateral = new SplitLiquidationCollateral();
    }
}
