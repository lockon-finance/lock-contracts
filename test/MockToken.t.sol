// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import {MockToken} from "../contracts/MockToken.sol";

contract MockTokenTest is Test {
    MockToken public token;
    address public owner = address(0x123);
    address public user = address(0x456);

    function setUp() public {
        token = new MockToken("Mock Token", "MTK", owner);
    }

    function test_deployment() public {
        assertEq(token.name(), "Mock Token");
        assertEq(token.symbol(), "MTK");
        assertEq(token.owner(), owner);
        assertEq(token.totalSupply(), 0);
    }

    function test_mint_by_owner() public {
        vm.startPrank(owner);
        uint256 initialTotalSupply = token.totalSupply();
        assertEq(initialTotalSupply, 0, "Initial total supply should be 0");

        uint256 mintAmount = 1000;
        token.mint(user, mintAmount);

        assertEq(token.balanceOf(user), mintAmount, "User balance should equal minted amount");

        uint256 newTotalSupply = token.totalSupply();
        assertEq(
            newTotalSupply,
            initialTotalSupply + mintAmount,
            "New total supply should equal initial supply plus minted amount"
        );
    }

    function test_burn() public {
        vm.startPrank(owner);
        uint256 initialMintAmount = 1000;
        token.mint(user, initialMintAmount);

        uint256 initialTotalSupply = token.totalSupply();
        assertEq(initialTotalSupply, initialMintAmount, "Initial total supply should equal initial minted amount");
        assertEq(token.balanceOf(user), initialMintAmount, "Initial user balance should equal initial minted amount");
        vm.stopPrank();
        uint256 burnAmount = 500;
        vm.startPrank(user);
        token.burn(burnAmount);

        uint256 expectedRemainingBalance = initialMintAmount - burnAmount;
        assertEq(
            token.balanceOf(user),
            expectedRemainingBalance,
            "User balance after burn should equal initial balance minus burned amount"
        );

        uint256 newTotalSupply = token.totalSupply();
        assertEq(
            newTotalSupply,
            initialTotalSupply - burnAmount,
            "New total supply should equal initial supply minus burned amount"
        );
    }

    function test_ownership_transfer() public {
        vm.startPrank(owner);
        token.transferOwnership(user);

        assertEq(token.owner(), user, "Ownership should be transferred to user");
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", owner));
        token.transferOwnership(user);
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", owner));
        token.mint(address(0x123), 1000);
        vm.stopPrank();

        address newOwner = address(0x456);
        vm.startPrank(user);
        token.transferOwnership(newOwner);
        assertEq(token.owner(), newOwner, "Ownership should be transferred to newOwner");
        vm.stopPrank();

        vm.startPrank(newOwner);
        token.mint(address(0x789), 2000);
        assertEq(token.balanceOf(address(0x789)), 2000, "New owner should be able to mint tokens");
    }
}
