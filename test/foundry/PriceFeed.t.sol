// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import { IPriceOracle } from "../../contracts/Oracles/Interfaces/IPriceOracle.sol";
import { ChainlinkPriceOracle } from "../../contracts/Oracles/ChainlinkPriceOracle.sol";
import { TellorPriceOracle } from "../../contracts/Oracles/TellorPriceOracle.sol";
import { PriceFeed, IPriceFeed } from "../../contracts/PriceFeed.sol";
import { MockChainlink } from "../TestContracts/MockChainlink.sol";
import { MockTellor } from "../TestContracts/MockTellor.sol";
import { PriceFeedTester } from "../TestContracts/PriceFeedTester.sol";

contract PriceFeedTest is Test {
    MockChainlink public mockChainlink;
    ChainlinkPriceOracle public chainlinkPriceOracle;
    MockTellor public mockTellor;
    TellorPriceOracle public tellorPriceOracle;

    PriceFeedTester public priceFeed;

    address public randomAddress;

    function setUp() public {
        randomAddress = makeAddr("randomAddress");

        mockChainlink = new MockChainlink();
        chainlinkPriceOracle = new ChainlinkPriceOracle(mockChainlink);
        mockTellor = new MockTellor();
        tellorPriceOracle = new TellorPriceOracle(mockTellor);

        _fillCorrectDataForChainlinkOracle();

        priceFeed = new PriceFeedTester(chainlinkPriceOracle, tellorPriceOracle);
    }

    function testCannotCreateContract() public {
        vm.expectRevert(IPriceFeed.InvalidPrimaryOracle.selector);
        new PriceFeed(IPriceOracle(address(0)), IPriceOracle(address(0)));

        MockChainlink newMockChainlink = new MockChainlink();
        ChainlinkPriceOracle newChainlinkPriceOracle = new ChainlinkPriceOracle(newMockChainlink);
        vm.expectRevert(IPriceFeed.PrimaryOracleBrokenOrFrozenOrBadResult.selector);
        new PriceFeed(newChainlinkPriceOracle, IPriceOracle(address(0)));

        vm.expectRevert(IPriceFeed.InvalidSecondaryOracle.selector);
        new PriceFeed(chainlinkPriceOracle, IPriceOracle(address(0)));
    }

    function testSetPrimaryOracle() public {
        ChainlinkPriceOracle newChainlinkPriceOracle = new ChainlinkPriceOracle(mockChainlink);
        priceFeed.setPrimaryOracle(newChainlinkPriceOracle);

        assertEq(address(newChainlinkPriceOracle), address(priceFeed.primaryOracle()));
    }

    function testCannotSetPrimaryOracle() public {
        vm.expectRevert(IPriceFeed.InvalidPrimaryOracle.selector);
        priceFeed.setPrimaryOracle(IPriceOracle(address(0)));

        MockChainlink newMockChainlink = new MockChainlink();
        ChainlinkPriceOracle newChainlinkPriceOracle = new ChainlinkPriceOracle(newMockChainlink);
        vm.expectRevert(IPriceFeed.PrimaryOracleBrokenOrFrozenOrBadResult.selector);
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
        vm.expectRevert(IPriceFeed.InvalidSecondaryOracle.selector);
        priceFeed.setSecondaryOracle(IPriceOracle(address(0)));

        MockTellor newMockTellor = new MockTellor();
        TellorPriceOracle newTellorPriceOracle = new TellorPriceOracle(newMockTellor);

        vm.prank(randomAddress);
        vm.expectRevert("Ownable: caller is not the owner");
        priceFeed.setSecondaryOracle(newTellorPriceOracle);
    }

    // Primary oracle working: fetchPrice should return the correct price, taking into account the number of decimal
    // digits on the aggregator
    function testFetchPricePrimaryOracleWorking() public {
        // Oracle price price is 10.00000000
        mockChainlink.setDecimals(8);
        mockChainlink.setPrevPrice(10 ** 8);
        mockChainlink.setPrice(10 ** 8);
        priceFeed.fetchPrice();
        uint256 price = priceFeed.lastGoodPrice();
        // Check Raft PriceFeed gives 10, with 18 digit precision
        assertEq(price, 10 ** 18);

        // Oracle price is 1e9
        mockChainlink.setDecimals(0);
        mockChainlink.setPrevPrice(10 ** 8);
        mockChainlink.setPrice(10 ** 8);
        priceFeed.fetchPrice();
        price = priceFeed.lastGoodPrice();
        // Check Raft PriceFeed gives 1e9, with 18 digit precision
        assertEq(price, 10 ** 26);

        // Oracle price is 0.0001
        mockChainlink.setDecimals(18);

        mockChainlink.setPrevPrice(10 ** 14);
        mockChainlink.setPrice(10 ** 14);
        priceFeed.fetchPrice();
        price = priceFeed.lastGoodPrice();
        // Check Raft PriceFeed gives 0.0001 with 18 digit precision
        assertEq(price, 10 ** 14);

        // Oracle price is 1234.56789
        mockChainlink.setDecimals(5);
        mockChainlink.setPrevPrice(123_456_789);
        mockChainlink.setPrice(123_456_789);
        priceFeed.fetchPrice();
        price = priceFeed.lastGoodPrice();
        // Check Raft PriceFeed gives 0.0001 with 18 digit precision
        assertEq(price, 1_234_567_890_000_000_000_000);
    }

    // --- Primary oracle breaks ---

    // Primary oracle breaks, secondary working: fetchPrice should return the correct secondary oracle price, taking
    // into account secondary oracle 6-digit granularity
    function testFetchPricePrimaryOracleBreak() public {
        // Primary oracle breaks with negative price
        mockChainlink.setPrevPrice(10 ** 7);
        mockChainlink.setPrice(-5000);

        mockTellor.setPrice(123 * 10 ** 6);
        mockChainlink.setUpdateTime(0);

        priceFeed.fetchPrice();

        uint256 price = priceFeed.lastGoodPrice();
        assertEq(price, 123 * 10 ** 18);

        // Secondary oracle price is 10 at 6-digit precision
        mockTellor.setPrice(10 ** 6);
        priceFeed.fetchPrice();
        price = priceFeed.lastGoodPrice();
        // Check Raft PriceFeed gives 10, with 18 digit precision
        assertEq(price, 10 ** 18);

        // Secondary oracle price is 1e9 at 6-digit precision
        mockTellor.setPrice(10 ** 14);
        priceFeed.fetchPrice();
        price = priceFeed.lastGoodPrice();
        // Check Raft PriceFeed gives 1e9, with 18 digit precision
        assertEq(price, 10 ** 26);

        // Secondary oracle price is 0.0001 at 6-digit precision
        mockTellor.setPrice(100);
        priceFeed.fetchPrice();
        price = priceFeed.lastGoodPrice();
        // Check Raft PriceFeed gives 0.0001 with 18 digit precision
        assertEq(price, 10 ** 14);

        // Secondary oracle price is 1234.56789 at 6-digit precision
        mockTellor.setPrice(1_234_567_890);
        priceFeed.fetchPrice();
        price = priceFeed.lastGoodPrice();
        // Check Raft PriceFeed gives 0.0001 with 18 digit precision
        assertEq(price, 1_234_567_890_000_000_000_000);
    }

    // Primary oracle broken by zero timestamp, secondary oracle working, return secondary oracle price
    function testFetchPricePrimaryOracleBreakZeroTimestamp() public {
        // Primary oracle breaks with zero timestamp
        mockChainlink.setPrevPrice(999 * 10 ** 8);
        mockChainlink.setPrice(999 * 10 ** 8);
        priceFeed.setLastGoodPrice(999 * 10 ** 18);

        mockTellor.setPrice(123 * 10 ** 6);
        mockChainlink.setUpdateTime(0);

        priceFeed.fetchPrice();

        uint256 price = priceFeed.lastGoodPrice();
        assertEq(price, 123 * 10 ** 18);
    }

    // Primary oracle broken by future timestamp, secondary oracle working, return secondary oracle price
    function testFetchPricePrimaryOracleBreakFutureTimestamp() public {
        // Primary oracle breaks with future timestamp
        mockChainlink.setPrevPrice(999 * 10 ** 8);
        mockChainlink.setPrice(999 * 10 ** 8);
        priceFeed.setLastGoodPrice(999 * 10 ** 18);

        mockTellor.setPrice(123 * 10 ** 6);
        mockChainlink.setUpdateTime(block.timestamp + 1000);

        priceFeed.fetchPrice();

        uint256 price = priceFeed.lastGoodPrice();
        assertEq(price, 123 * 10 ** 18);
    }

    // Primary oracle broken by negative price, secondary oracle working, return secondary oracle price
    function testFetchPricePrimaryOracleBreakNegativePrice() public {
        mockChainlink.setPrevPrice(999 * 10 ** 8);
        priceFeed.setLastGoodPrice(999 * 10 ** 18);

        mockTellor.setPrice(123 * 10 ** 6);
        mockChainlink.setPrice(-5000);

        priceFeed.fetchPrice();

        uint256 price = priceFeed.lastGoodPrice();
        assertEq(price, 123 * 10 ** 18);
    }

    // Primary oracle broken - decimals call reverted, secondary oracle working, return secondary oracle price
    function testFetchPricePrimaryOracleBreakDecimalsRevert() public {
        mockChainlink.setPrevPrice(999 * 10 ** 8);
        mockChainlink.setPrice(999 * 10 ** 8);
        priceFeed.setLastGoodPrice(999 * 10 ** 18);

        mockTellor.setPrice(123 * 10 ** 6);
        mockChainlink.setDecimalsRevert();

        priceFeed.fetchPrice();

        uint256 price = priceFeed.lastGoodPrice();
        assertEq(price, 123 * 10 ** 18);
    }

    // Primary oracle latest round call reverted, secondary oracle working, return the secondary oracle price
    function testFetchPricePrimaryOracleLatestRoungCallRevert() public {
        mockChainlink.setPrevPrice(999 * 10 ** 8);
        mockChainlink.setPrice(999 * 10 ** 8);
        priceFeed.setLastGoodPrice(999 * 10 ** 18);

        mockTellor.setPrice(123 * 10 ** 6);
        mockChainlink.setLatestRevert();

        priceFeed.fetchPrice();

        uint256 price = priceFeed.lastGoodPrice();
        assertEq(price, 123 * 10 ** 18);
    }

    // --- Primary oracle timeout ---

    // Primary oracle frozen, secondary oracle working: return secondary oracle price
    function testFetchPricePrimaryOracleFrozenSecondaryWorking() public {
        mockChainlink.setPrevPrice(999 * 10 ** 8);
        mockChainlink.setPrice(999 * 10 ** 8);
        priceFeed.setLastGoodPrice(999 * 10 ** 18);

        skip(4 hours + 1); // Fast forward 4 hours

        // Secondary oracle price is recent
        mockTellor.setUpdateTime(block.timestamp);
        mockTellor.setPrice(123 * 10 ** 6);

        priceFeed.fetchPrice();

        uint256 price = priceFeed.lastGoodPrice();
        assertEq(price, 123 * 10 ** 18);
    }

    // Primary oracle frozen, secondary oracle frozen: return last good price
    function testFetchPricePrimaryOracleFrozenSecondaryOracleFrozen() public {
        mockChainlink.setPrevPrice(999 * 10 ** 8);
        mockChainlink.setPrice(999 * 10 ** 8);
        priceFeed.setLastGoodPrice(999 * 10 ** 18);

        mockTellor.setPrice(123 * 10 ** 6);

        skip(4 hours + 1); // Fast forward 4 hours

        // check secondary oracle price timestamp is out of date by > 4 hours
        uint256 tellorUpdateTime = mockTellor.getTimestampbyRequestIDandIndex(0, 0);
        assertLt(tellorUpdateTime, block.timestamp - 4 hours);

        priceFeed.fetchPrice();
        uint256 price = priceFeed.lastGoodPrice();
        // Expect lastGoodPrice has not updated
        assertEq(price, 999 * 10 ** 18);
    }

    // Primary oracle times out, secondary oracle broken by 0 price: return last good price
    function testFetchPricePrimaryOracleTimeoutSecondaryOracleBreakZeroPrice() public {
        mockChainlink.setPrevPrice(999 * 10 ** 8);
        mockChainlink.setPrice(999 * 10 ** 8);
        priceFeed.setLastGoodPrice(999 * 10 ** 18);

        skip(4 hours + 1); // Fast forward 4 hours

        mockTellor.setPrice(0);

        priceFeed.fetchPrice();
        uint256 price = priceFeed.lastGoodPrice();

        // Expect lastGoodPrice has not updated
        assertEq(price, 999 * 10 ** 18);
    }

    // Primary oracle is out of date by <4hrs: return primary price
    function testFetchPricePrimaryOracleNotTimeout() public {
        mockChainlink.setPrevPrice(1234 * 10 ** 8);
        mockChainlink.setPrice(1234 * 10 ** 8);
        skip(4 hours);

        priceFeed.fetchPrice();
        uint256 price = priceFeed.lastGoodPrice();
        assertEq(price, 1234 * 10 ** 18);
    }

    // --- Primary oracle price deviation ---

    // Primary oracle price drop of >50%, return the secondary oracle price
    function testFetchPricePrimaryOraclePriceDropMoreThan50Percent() public {
        priceFeed.setLastGoodPrice(200 * 10 ** 18);

        mockTellor.setPrice(203 * 10 ** 4);
        mockChainlink.setPrevPrice(2 * 10 ** 8); // price = 2
        mockChainlink.setPrice(99_999_999); // price drops to 0.99999999: a drop of > 50% from previous

        priceFeed.fetchPrice();

        uint256 price = priceFeed.lastGoodPrice();
        assertEq(price, 203 * 10 ** 16);
    }

    // Primary oracle price drop of 50%, return the primary oracle price
    function testFetchPricePrimaryOracleDropOf50Percent() public {
        priceFeed.setLastGoodPrice(2 * 10 ** 18);

        mockTellor.setPrice(203 * 10 ** 4);
        mockChainlink.setPrevPrice(2 * 10 ** 8); // price = 2
        mockChainlink.setPrice(10 ** 8); // price drops to 1

        priceFeed.fetchPrice();

        uint256 price = priceFeed.lastGoodPrice();
        assertEq(price, 10 ** 18);
    }

    // Primary oracle price drop of <50%, return primary oracle price
    function testFetchPricePrimaryOraclePriceDropLessThan50Percent() public {
        priceFeed.setLastGoodPrice(2 * 10 ** 18);

        mockTellor.setPrice(203 * 10 ** 4);
        mockChainlink.setPrevPrice(2 * 10 ** 8); // price = 2
        mockChainlink.setPrice(100_000_001); // price drops to 1.00000001:  a drop of < 50% from previous

        priceFeed.fetchPrice();

        uint256 price = priceFeed.lastGoodPrice();
        assertEq(price, 100_000_001 * 10 ** 10);
    }

    // Primary oracle price increase of >100%, return secondary oracle price
    function testFetchPricePrimaryOraclePriceIncreaseMoreThan100Percent() public {
        priceFeed.setLastGoodPrice(2 * 10 ** 18);

        mockTellor.setPrice(203 * 10 ** 4);
        mockChainlink.setPrevPrice(2 * 10 ** 8); // price = 2
        mockChainlink.setPrice(400_000_001); // price increases to 4.000000001: an increase of > 100% from previous

        priceFeed.fetchPrice();
        uint256 price = priceFeed.lastGoodPrice();
        assertEq(price, 203 * 10 ** 16);
    }

    // Primary oracle price increase of 100%, return primary oracle price
    function testFetchPricePrimaryOraclePriceIncreaseOf100Percent() public {
        priceFeed.setLastGoodPrice(2 * 10 ** 18);

        mockTellor.setPrice(203 * 10 ** 4);
        mockChainlink.setPrevPrice(2 * 10 ** 8); // price = 2
        mockChainlink.setPrice(4 * 10 ** 8); // price increases to 4: an increase of 100% from previous

        priceFeed.fetchPrice();
        uint256 price = priceFeed.lastGoodPrice();
        assertEq(price, 4 * 10 ** 18);
    }

    // Primary oracle price increase of <100%, return primary oracle price
    function testFetchPricePrimaryOraclePriceIncreaseLessThan100Percent() public {
        priceFeed.setLastGoodPrice(2 * 10 ** 18);

        mockTellor.setPrice(203 * 10 ** 4);
        mockChainlink.setPrevPrice(2 * 10 ** 8); // price = 2
        mockChainlink.setPrice(399_999_999); // price increases to 3.99999999: an increase of < 100% from previous

        priceFeed.fetchPrice();
        uint256 price = priceFeed.lastGoodPrice();
        assertEq(price, 399_999_999 * 10 ** 10);
    }

    // Primary oracle price drop of >50% and secondary oracle price matches: return primary oracle price
    function testFetchPricePrimaryOraclePriceDropMoreThan50PercentSecondaryOraclePriceMatches() public {
        priceFeed.setLastGoodPrice(2 * 10 ** 18);

        mockChainlink.setPrevPrice(2 * 10 ** 8); // price = 2
        mockChainlink.setPrice(99_999_999); // price drops to 0.99999999: a drop of > 50% from previous
        mockTellor.setPrice(999_999); // Secondary oracle price drops to same value (at 6 decimals)

        priceFeed.fetchPrice();
        uint256 price = priceFeed.lastGoodPrice();
        assertEq(price, 99_999_999 * 10 ** 10);
    }

    // Primary oracle price drop of >50% and secondary oracle price within 5% of primary: return secondary oracle price
    function testFetchPricePrimaryOraclePriceDropMoreThan50PercentSecondaryOraclePriceWithin5Percent() public {
        priceFeed.setLastGoodPrice(2 * 10 ** 18);

        mockChainlink.setPrevPrice(1000 * 10 ** 8); // prev price = 1000
        mockChainlink.setPrice(100 * 10 ** 8); // price drops to 100: a drop of > 50% from previous
        mockTellor.setPrice(104_999_999); // Secondary oracle price drops to 104.99: price difference with new primary
            // oracle price is now just under 5%

        priceFeed.fetchPrice();
        uint256 price = priceFeed.lastGoodPrice();
        assertEq(price, 100 * 10 ** 18);
    }

    // Primary oracle price drop of >50% and secondary oracle live but not within 5% of primary: return secondary oracle
    // price
    function testFetchPricePrimaryOraclePriceDropMoreThan50PercentSecondaryOraclePriceNotWithin5Percent() public {
        priceFeed.setLastGoodPrice(2 * 10 ** 18);

        mockChainlink.setPrevPrice(1000 * 10 ** 8); // prev price = 1000
        mockChainlink.setPrice(100 * 10 ** 8); // price drops to 100: a drop of > 50% from previous
        mockTellor.setPrice(105_000_001); // Secondary oracle price drops to 105.000001: price difference with new
            // primary oracle price is now > 5%

        priceFeed.fetchPrice();
        uint256 price = priceFeed.lastGoodPrice();
        assertEq(price, 105_000_001 * 10 ** 12); // return secondary oracle price
    }

    // Primary oracle price drop of >50% and secondary oracle frozen: return last good price
    function testFetchPricePrimaryOracleDropMoreThan50PercentSecondaryOracleFrozen() public {
        priceFeed.setLastGoodPrice(1200 * 10 ** 18); // establish a "last good price" from the previous price fetch

        mockChainlink.setPrevPrice(1000 * 10 ** 8); // prev price = 1000
        mockChainlink.setPrice(100 * 10 ** 8); // price drops to 100: a drop of > 50% from previous
        mockTellor.setPrice(100 * 10 ** 8);

        // 4 hours pass with no secondary oracle updates
        skip(4 hours + 1);

        // check secondary oracle price timestamp is out of date by > 4 hours
        uint256 tellorUpdateTime = mockTellor.getTimestampbyRequestIDandIndex(0, 0);
        assertLt(tellorUpdateTime, block.timestamp - 4 hours);

        mockChainlink.setUpdateTime(block.timestamp);

        priceFeed.fetchPrice();
        uint256 price = priceFeed.lastGoodPrice();

        // Check that the returned price is the last good price
        assertEq(price, 1200 * 10 ** 18);
    }

    // --- Primary oracle fails and secondary oracle is broken ---

    // Primary oracle price drop of >50% and secondary is broken by 0 price: return last good price
    function testFetchPricePrimaryOracleDropMoreThan50PercentSecondaryOracleBrokenByZeroPrice() public {
        priceFeed.setLastGoodPrice(1200 * 10 ** 18); // establish a "last good price" from the previous price fetch

        mockTellor.setPrice(1300 * 10 ** 6);

        // Make mock primary oracle price deviate too much
        mockChainlink.setPrevPrice(2 * 10 ** 8); // price = 2
        mockChainlink.setPrice(99_999_999); // price drops to 0.99999999: a drop of > 50% from previous

        // Make mock secondary oracle return 0 price
        mockTellor.setPrice(0);

        priceFeed.fetchPrice();
        uint256 price = priceFeed.lastGoodPrice();

        // Check that the returned price is in fact the previous price
        assertEq(price, 1200 * 10 ** 18);
    }

    // Primary oracle price drop of >50% and secondary oracle is broken by 0 timestamp: return last good price
    function testFetchPricePrimaryOracleDropMoreThan50PercentSecondaryOracleBrokenByZeroTimestamp() public {
        priceFeed.setLastGoodPrice(1200 * 10 ** 18); // establish a "last good price" from the previous price fetch

        mockTellor.setPrice(1300 * 10 ** 6);

        // Make mock primary oracle price deviate too much
        mockChainlink.setPrevPrice(2 * 10 ** 8); // price = 2
        mockChainlink.setPrice(99_999_999); // price drops to 0.99999999: a drop of > 50% from previous

        // Make mock secondary oracle return 0 timestamp
        mockTellor.setUpdateTime(0);

        priceFeed.fetchPrice();
        uint256 price = priceFeed.lastGoodPrice();

        // Check that the returned price is in fact the previous price
        assertEq(price, 1200 * 10 ** 18);
    }

    // Primary oracle price drop of >50% and secondary oracle is broken by future timestamp: return last good price
    function testFetchPricePrimaryOracleDropMoreThan50PercentSecondaryOracleBrokenByFutureTimestamp() public {
        priceFeed.setLastGoodPrice(1200 * 10 ** 18); // establish a "last good price" from the previous price fetch

        mockTellor.setPrice(1300 * 10 ** 6);

        // Make mock primary oracle price deviate too much
        mockChainlink.setPrevPrice(2 * 10 ** 8); // price = 2
        mockChainlink.setPrice(99_999_999); // price drops to 0.99999999: a drop of > 50% from previous

        // Make mock secondary oracle return a future timestamp
        mockTellor.setUpdateTime(block.timestamp + 10_000);

        priceFeed.fetchPrice();
        uint256 price = priceFeed.lastGoodPrice();

        // Check that the returned price is in fact the previous price
        assertEq(price, 1200 * 10 ** 18);
    }

    // Primary oracle is working and secondary oracle is working - return primary oracle price
    function testFetchPricePrimaryOracleWorkingSecondaryOracleWorking() public {
        priceFeed.setLastGoodPrice(1200 * 10 ** 18);

        mockChainlink.setPrevPrice(101 * 10 ** 8);
        mockChainlink.setPrice(102 * 10 ** 8);

        mockTellor.setPrice(103 * 10 ** 18);

        priceFeed.fetchPrice();
        uint256 price = priceFeed.lastGoodPrice();

        // Check that the returned price is current primary oracle price
        assertEq(price, 102 * 10 ** 18);
    }

    // Primary oracle is working and secondary oracle freezes - return primary oracle price
    function testFetchPricePrimaryOracleWorkingSecondaryOracleFreezes() public {
        priceFeed.setLastGoodPrice(1200 * 10 ** 18);

        mockChainlink.setPrevPrice(101 * 10 ** 8);
        mockChainlink.setPrice(102 * 10 ** 8);

        mockTellor.setPrice(103 * 10 ** 18);

        // 4 hours pass with no secondary oracle updates
        skip(4 hours + 1);

        // check secondary oracle price timestamp is out of date by > 4 hours
        uint256 tellorUpdateTime = mockTellor.getTimestampbyRequestIDandIndex(0, 0);
        assertLt(tellorUpdateTime, block.timestamp - 4 hours);

        mockChainlink.setUpdateTime(block.timestamp); // Primary oracle's price is current

        priceFeed.fetchPrice();
        uint256 price = priceFeed.lastGoodPrice();

        // Check that the returned price is current primary oracle price
        assertEq(price, 102 * 10 ** 18);
    }

    // Primary oracle is working and secondary oracle breaks: return primary oracle price
    function testFetchPricePrimaryOracleWorkingSecondaryOracleBreaks() public {
        priceFeed.setLastGoodPrice(1200 * 10 ** 18); // establish a "last good price" from the previous price fetch

        mockChainlink.setPrevPrice(101 * 10 ** 8);
        mockChainlink.setPrice(102 * 10 ** 8);

        mockTellor.setPrice(0);

        priceFeed.fetchPrice();
        uint256 price = priceFeed.lastGoodPrice();

        // Check that the returned price is current primary oracle price
        assertEq(price, 102 * 10 ** 18);
    }

    // --- Helper functions ---

    function _fillCorrectDataForChainlinkOracle() private {
        // Set primary oracle latest and prev round Id's to non-zero
        mockChainlink.setLatestRoundId(3);
        mockChainlink.setPrevRoundId(2);

        //Set current and prev prices in both oracles
        mockChainlink.setPrice(100 ** 18);
        mockChainlink.setPrevPrice(100 ** 18);
        mockChainlink.setUpdateTime(block.timestamp);
        mockTellor.setPrice(100 ** 18);

        // Set mock price updateTimes in both oracles to very recent
        mockChainlink.setUpdateTime(block.timestamp);
        mockTellor.setUpdateTime(block.timestamp);
    }
}
