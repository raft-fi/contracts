// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {CallerIsNotPositionManager} from "../contracts/Interfaces/IPositionManagerDependent.sol";
import {RToken, IRToken, FlashFeePercentageTooBig} from "../contracts/RToken.sol";
import {TestSetup} from "./utils/TestSetup.t.sol";

contract RTokenTest is TestSetup {
    IRToken public token;

    function setUp() public override {
        super.setUp();

        token = new RToken(address(POSITION_MANAGER), FEE_RECIPIENT);
    }

    function testMaxFlashMint(uint256 simulatedTotalSupply) public {
        vm.prank(address(token.positionManager()));
        token.mint(ALICE, simulatedTotalSupply);

        uint256 technicalLimit = type(uint256).max - simulatedTotalSupply;
        uint256 supplyLimit = simulatedTotalSupply / 10;

        assertEq(token.maxFlashLoan(address(token)), technicalLimit < supplyLimit ? technicalLimit : supplyLimit);
    }

    function testMaxFlashMintIsZero() public {
        assertEq(token.maxFlashLoan(address(2)), 0);
    }

    function testSetFeeRecipient() public {
        token.setFeeRecipient(FEE_RECIPIENT);
        assertEq(token.feeRecipient(), FEE_RECIPIENT);

        vm.prank(ALICE);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        token.setFeeRecipient(address(1));
    }

    function testFlashFee(uint256 amount, uint256 percentage) public {
        percentage = bound(percentage, 0, 500);
        amount = bound(amount, 0, type(uint256).max / 500 - 1);
        token.setFlashMintFeePercentage(percentage);
        assertEq(token.flashFee(address(token), amount), amount * percentage / 10_000);
    }

    function testSetFlashFeePercentage() public {
        vm.prank(ALICE);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        token.setFlashMintFeePercentage(1);

        vm.expectRevert(abi.encodeWithSelector(FlashFeePercentageTooBig.selector, 1_000));
        token.setFlashMintFeePercentage(1_000);

        token.setFlashMintFeePercentage(500);
        assertEq(token.flashMintFeePercentage(), 500);
    }

    function testMint(uint256 amount) public {
        vm.prank(address(token.positionManager()));
        token.mint(ALICE, amount);
        assertEq(token.balanceOf(ALICE), amount);
    }

    function testUnauthorizedMintOrBurn() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(CallerIsNotPositionManager.selector, ALICE));
        token.mint(ALICE, 1);

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(CallerIsNotPositionManager.selector, ALICE));
        token.burn(ALICE, 1);
    }

    function testBurn(uint256 amountToMint, uint256 amountToBurn) public {
        vm.prank(address(token.positionManager()));
        token.mint(ALICE, amountToMint);

        vm.prank(address(token.positionManager()));
        if (amountToBurn > amountToMint) {
            vm.expectRevert(bytes("ERC20: burn amount exceeds balance"));
        }
        token.burn(ALICE, amountToBurn);
        assertEq(token.balanceOf(ALICE), amountToBurn > amountToMint ? amountToMint : amountToMint - amountToBurn);
    }
}
