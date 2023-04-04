// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import "../../../contracts/Interfaces/IPositionManager.sol";
import "../../../contracts/Interfaces/IPriceFeed.sol";
import "../../TestContracts/WstETHTokenMock.sol";

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

    // Fee recipients
    address public constant FEE_RECIPIENT = address(100);
    address public constant NEW_FEE_RECIPIENT = address(101);

    // Mocked contract addresses
    IPriceFeed public constant PRICE_FEED = IPriceFeed(address(12345));
    IERC20 public constant COLLATERAL_TOKEN = IERC20(address(23456));
    IPositionManager public constant POSITION_MANAGER = IPositionManager(address(34567));

    // Collateral token mock
    WstETHTokenMock public collateralToken;
}
