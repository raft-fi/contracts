// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IPositionManager,
    PositionManagerOnlyOnePositionInSystem,
    NewICRLowerThanMCR
} from "../contracts/Interfaces/IPositionManager.sol";
import {PositionManager} from "../contracts/PositionManager.sol";
import {PositionsListDoesNotContainNode} from "../contracts/SortedPositions.sol";
import {MathUtils} from "../contracts/Dependencies/MathUtils.sol";
import {PriceFeedTestnet} from "./TestContracts/PriceFeedTestnet.sol";
import {TokenMock} from "./TestContracts/TokenMock.sol";
import {WstETHTokenMock} from "./TestContracts/WstETHTokenMock.sol";
import {PositionManagerUtils} from "./utils/PositionManagerUtils.sol";
import {TestSetup} from "./utils/TestSetup.t.sol";

contract PositionManagerMultiCollateralTest is TestSetup {
    uint256 public constant POSITIONS_SIZE = 10;
    uint256 public constant LIQUIDATION_PROTOCOL_FEE = 0;
    uint256 public constant DEFAULT_PRICE = 200e18;

    PriceFeedTestnet public priceFeed;
    IPositionManager public positionManager;

    TokenMock public collateralTokenSecond;
    PriceFeedTestnet public priceFeedSecond;

    address public randomAddress;

    function setUp() public override {
        super.setUp();

        positionManager = new PositionManager(
            LIQUIDATION_PROTOCOL_FEE,
            new address[](0)
        );

        priceFeed = new PriceFeedTestnet();
        positionManager.addCollateralToken(collateralToken, priceFeed, POSITIONS_SIZE);

        collateralTokenSecond = new TokenMock();
        priceFeedSecond = new PriceFeedTestnet();
        positionManager.addCollateralToken(collateralTokenSecond, priceFeedSecond, POSITIONS_SIZE);

        randomAddress = makeAddr("randomAddress");

        collateralToken.mint(ALICE, 10e36);
        collateralToken.mint(BOB, 10e36);
        collateralToken.mint(CAROL, 10e36);
    }

    function testAddCollateralToken() public {
        TokenMock collateralTokenThird = new TokenMock();
        PriceFeedTestnet priceFeedThird = new PriceFeedTestnet();

        assertEq(address(positionManager.raftCollateralTokens(collateralTokenThird)), address(0));
        positionManager.addCollateralToken(collateralTokenThird, priceFeedThird, POSITIONS_SIZE);

        assertEq(positionManager.raftCollateralTokens(collateralTokenThird) != IERC20(address(0)), true);
    }

    function testCannotAddCollateralToken() public {
        vm.expectRevert(IPositionManager.CollateralTokenAlreadyAdded.selector);
        positionManager.addCollateralToken(collateralTokenSecond, priceFeedSecond, POSITIONS_SIZE);

        TokenMock collateralTokenThird = new TokenMock();
        PriceFeedTestnet priceFeedThird = new PriceFeedTestnet();
        vm.prank(randomAddress);
        vm.expectRevert("Ownable: caller is not the owner");
        positionManager.addCollateralToken(collateralTokenThird, priceFeedThird, POSITIONS_SIZE);
    }
}
