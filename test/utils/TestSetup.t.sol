// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {IPositionManager} from "../../contracts/Interfaces/IPositionManager.sol";
import {IPriceFeed} from "../../contracts/Interfaces/IPriceFeed.sol";
import {ISplitLiquidationCollateral} from "../../contracts/Interfaces/ISplitLiquidationCollateral.sol";
import {WstETHTokenMock} from "../TestContracts/WstETHTokenMock.sol";

contract TestSetup is Test {
    struct CollateralDebt {
        uint256 collateral;
        uint256 debt;
    }

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
    IPriceFeed public constant PRICE_FEED = IPriceFeed(address(12345));
    IPositionManager public constant POSITION_MANAGER = IPositionManager(address(34567));
    ISplitLiquidationCollateral public constant SPLIT_LIQUIDATION_COLLATERAL =
        ISplitLiquidationCollateral(address(56789));

    // Collateral token mock
    WstETHTokenMock public collateralToken;

    function setUp() public virtual {
        collateralToken = new WstETHTokenMock();
    }
}
