// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../contracts/ERC20Indexable.sol";

contract ERC20IndexableTest is Test {
    ERC20Indexable private token;
    address private constant POS_MANAGER = address(123);
    address private constant USER = address(234);

    function setUp() public {
        token = new ERC20Indexable(POS_MANAGER, "name", "symbol");
    }

    function testMintWithIndexChange(
        uint256 initialSupply,
        uint256 amountToMint,
        uint256 supplyDecrease
    ) public {
        initialSupply = bound(initialSupply, 1e18, 1e32);
        supplyDecrease = bound(supplyDecrease, 1, initialSupply / 2);
        amountToMint = bound(amountToMint, 1, 1e30);

        vm.startPrank(POS_MANAGER);
        token.mint(address(this), initialSupply);
        token.mint(USER, amountToMint);
        token.burn(address(this), supplyDecrease);
        token.setIndex(initialSupply);

    }

    function testMintBurnWithIndexChange(
        uint256 initialSupply,
        uint256 supplyDecrease,
        uint256 amountToMint,
        uint256 amountToBurn
    ) public {
        initialSupply = bound(initialSupply, 1e18, 1e32);
        supplyDecrease = bound(supplyDecrease, 1, initialSupply / 2);
        amountToMint = bound(amountToMint, 2000, 1e30);
        amountToBurn = bound(amountToBurn, 500, amountToMint / 2);

        vm.startPrank(POS_MANAGER);
        token.mint(address(this), initialSupply);
        token.burn(address(this), supplyDecrease);
        token.setIndex(initialSupply);

        token.mint(USER, amountToMint);
        token.burn(USER, amountToBurn);

        assertApproxEqAbs(token.balanceOf(USER), amountToMint - amountToBurn, 2);
    }

    function testMintBurnAllWithIndexChange(
        uint256 initialSupply,
        uint256 supplyDecrease,
        uint256 amountToMint
    ) public {
        initialSupply = bound(initialSupply, 1e18, 1e32);
        supplyDecrease = bound(supplyDecrease, 1, initialSupply / 2);
        amountToMint = bound(amountToMint, 1, 1e30);

        vm.startPrank(POS_MANAGER);
        token.mint(address(this), initialSupply);
        token.mint(USER, amountToMint);
        token.burn(address(this), supplyDecrease);
        token.setIndex(initialSupply);

        assertEq(token.balanceOf(USER), amountToMint * token.currentIndex() / token.INDEX_PRECISION());

        token.burn(USER, token.balanceOf(USER));

        assertEq(token.balanceOf(USER), 0);
    }
}