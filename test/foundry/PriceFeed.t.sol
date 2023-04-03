// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../../contracts/Oracles/ChainlinkPriceOracle.sol";
import "../../contracts/Oracles/TellorPriceOracle.sol";
import "../../contracts/PriceFeed.sol";
import "../TestContracts/MockAggregator.sol";
import "../TestContracts/MockTellor.sol";

contract PriceFeedTest is Test {

    MockAggregator public mockAggregator;
    ChainlinkPriceOracle public chainlinkPriceOracle;
    MockTellor public mockTellor;
    TellorPriceOracle public tellorPriceOracle;

    PriceFeed public priceFeed;

    address public randomAddress;

    function setUp() public {
        randomAddress = makeAddr("randomAddress");

        mockAggregator = new MockAggregator();
        chainlinkPriceOracle = new ChainlinkPriceOracle(mockAggregator);
        mockTellor = new MockTellor();
        tellorPriceOracle = new TellorPriceOracle(mockTellor);

        _fillCorrectDataForChainlinkOracle();

        priceFeed = new PriceFeed(chainlinkPriceOracle, tellorPriceOracle);
    }

    function testCannotCreateContract() public {
        vm.expectRevert(InvalidPrimaryOracle.selector);
        new PriceFeed(IPriceOracle(address(0)), IPriceOracle(address(0)));

        MockAggregator newMockAggregator = new MockAggregator();
        ChainlinkPriceOracle newChainlinkPriceOracle = new ChainlinkPriceOracle(newMockAggregator);
        vm.expectRevert(PrimaryOracleBrokenOrFrozenOrBadResult.selector);
        new PriceFeed(newChainlinkPriceOracle, IPriceOracle(address(0)));

        vm.expectRevert(InvalidSecondaryOracle.selector);
        new PriceFeed(chainlinkPriceOracle, IPriceOracle(address(0)));
    }

    function testSetPrimaryOracle() public {
        ChainlinkPriceOracle newChainlinkPriceOracle = new ChainlinkPriceOracle(mockAggregator);
        priceFeed.setPrimaryOracle(newChainlinkPriceOracle);

        assertEq(address(newChainlinkPriceOracle), address(priceFeed.primaryOracle()));
    }

    function testCannotSetPrimaryOracle() public {
        vm.expectRevert(InvalidPrimaryOracle.selector);
        priceFeed.setPrimaryOracle(IPriceOracle(address(0)));

        MockAggregator newMockAggregator = new MockAggregator();
        ChainlinkPriceOracle newChainlinkPriceOracle = new ChainlinkPriceOracle(newMockAggregator);
        vm.expectRevert(PrimaryOracleBrokenOrFrozenOrBadResult.selector);
        priceFeed.setPrimaryOracle(newChainlinkPriceOracle);

        vm.prank(randomAddress);
        vm.expectRevert("Ownable: caller is not the owner");
        priceFeed.setPrimaryOracle(newChainlinkPriceOracle);
    }

    function testSetSecondaryOracle() public {
        TellorPriceOracle newTellorPriceOracle = new TellorPriceOracle(mockTellor);
        priceFeed.setSecondaryOracle(newTellorPriceOracle);

        assertEq(address(newTellorPriceOracle), address(priceFeed.secondaryOracle()));
    }

    function testCannotSetSecondaryOracle() public {
        vm.expectRevert(InvalidSecondaryOracle.selector);
        priceFeed.setSecondaryOracle(IPriceOracle(address(0)));

        MockTellor newMockTellor = new MockTellor();
        TellorPriceOracle newTellorPriceOracle = new TellorPriceOracle(newMockTellor);

        vm.prank(randomAddress);
        vm.expectRevert("Ownable: caller is not the owner");
        priceFeed.setSecondaryOracle(newTellorPriceOracle);
    }

    // Set correct data for primary oracle
    function _fillCorrectDataForChainlinkOracle() private {
        mockAggregator.setLatestRoundId(3);
        mockAggregator.setPrevRoundId(2);
        mockAggregator.setPrice(100 ** 18);
        mockAggregator.setPrevPrice(100 ** 18);
        mockAggregator.setUpdateTime(block.timestamp);
    }
}
