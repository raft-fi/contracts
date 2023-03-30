// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/RToken.sol";

contract RTokenTest is Test {
    IPositionManager public constant POSITION_MANAGER = IPositionManager(address(12345));

    address public constant USER = address(1);
    address public constant FEE_RECIPIENT = address(2);

    IRToken public token;

    function setUp() public {
        token = new RToken(POSITION_MANAGER, FEE_RECIPIENT);
    }

    function testMaxFlashMint(uint256 simulatedTotalSupply) public {
        vm.prank(address(token.positionManager()));
        token.mint(USER, simulatedTotalSupply);

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

        vm.prank(USER);
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
        vm.prank(USER);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        token.setFlashMintFeePercentage(1);

        vm.expectRevert(abi.encodeWithSelector(FlashFeePercentageTooBig.selector, 1_000));
        token.setFlashMintFeePercentage(1_000);

        token.setFlashMintFeePercentage(500);
        assertEq(token.flashMintFeePercentage(), 500);
    }

    function testMint(uint256 amount) public {
        vm.prank(address(token.positionManager()));
        token.mint(USER, amount);
        assertEq(token.balanceOf(USER), amount);
    }

    function testUnauthorizedMintOrBurn() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(CallerIsNotPositionManager.selector, USER));
        token.mint(USER, 1);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(CallerIsNotPositionManager.selector, USER));
        token.burn(USER, 1);
    }

    function testBurn(uint256 amountToMint, uint256 amountToBurn) public {
        vm.prank(address(token.positionManager()));
        token.mint(USER, amountToMint);

        vm.prank(address(token.positionManager()));
        if (amountToBurn > amountToMint) {
            vm.expectRevert(bytes("ERC20: burn amount exceeds balance"));
        }
        token.burn(USER, amountToBurn);
        assertEq(token.balanceOf(USER), amountToBurn > amountToMint ? amountToMint : amountToMint - amountToBurn);
    }
}
