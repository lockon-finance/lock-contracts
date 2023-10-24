// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {LockToken} from "../contracts/LockToken.sol";

contract LockTokenTest is Test {
    LockToken public lockToken;
    address public owner = address(bytes20(bytes("owner")));
    address public operator = address(bytes20(bytes("operator")));
    address public accountOne = address(1);
    address public accountTwo = address(2);
    error ERC20InsufficientBalance(
        address sender,
        uint256 balance,
        uint256 needed
    );
    error ERC20InsufficientAllowance(
        address spender,
        uint256 allowance,
        uint256 needed
    );

    function setUp() public {
        vm.prank(address(owner));
        lockToken = new LockToken();
    }

    function test__initilize_and_mint_succeed() public {
        vm.prank(address(owner));
        lockToken.initialize("LockToken", "LOCK", address(owner), operator);
        uint256 ownerBalance = lockToken.balanceOf(address(owner));
        uint256 operatorBalance = lockToken.balanceOf(address(operator));
        assertEq(ownerBalance, 6_000_000_000 * 1e18);
        assertEq(operatorBalance, 4_000_000_000 * 1e18);
    }

    function test__transfer_tokens_fuzz(uint32 amount) public {
        vm.startPrank(address(owner));
        lockToken.initialize("LockToken", "LOCK", address(owner), operator);
        bool transferPassed = lockToken.transfer(address(accountOne), amount);
        vm.stopPrank();
        assertTrue(transferPassed);
    }

    function test__transfer_from_tokens_fuzz(uint32 amount) public {
        vm.startPrank(address(owner));
        lockToken.initialize("LockToken", "LOCK", address(owner), operator);
        lockToken.approve(address(operator), amount);
        vm.stopPrank();
        vm.prank(address(operator));
        bool transferPassed = lockToken.transferFrom(
            address(owner),
            address(accountOne),
            amount
        );
        assertTrue(transferPassed);
    }

    function test__cannot_transfer_exceed_amount() public {
        vm.startPrank(address(owner));
        lockToken.initialize("LockToken", "LOCK", address(owner), operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20InsufficientBalance.selector,
                address(owner),
                lockToken.balanceOf(address(owner)),
                6_000_000_001 * 1e18
            )
        );
        lockToken.transfer(address(accountOne), 6_000_000_001 * 1e18);
        vm.stopPrank();
    }

    function test__cannot_transfer_from_if_not_approve() public {
        vm.prank(address(owner));
        lockToken.initialize("LockToken", "LOCK", address(owner), operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20InsufficientAllowance.selector,
                address(operator),
                lockToken.allowance(address(owner), address(operator)),
                1000 * 1e18
            )
        );
        vm.prank(address(operator));
        lockToken.transferFrom(
            address(owner),
            address(accountOne),
            1000 * 1e18
        );
    }
}
