// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {LockToken} from "../contracts/LockToken.sol";

contract LockTokenTest is Test {
    LockToken public lockToken;
    address public owner = address(bytes20(bytes("owner")));
    address public operator = address(bytes20(bytes("operator")));
    address public accountOne = address(1);

    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    function setUp() public {
        vm.startPrank(owner);
        lockToken = new LockToken();
    }

    function test__initilize_and_mint_succeed() public {
        lockToken.initialize("LockToken", "LOCK", owner, operator);
        uint256 ownerBalance = lockToken.balanceOf(owner);
        uint256 operatorBalance = lockToken.balanceOf(operator);
        assertEq(ownerBalance, 6_000_000_000 * 1e18);
        assertEq(operatorBalance, 4_000_000_000 * 1e18);
    }

    function test__transfer_tokens_fuzz(uint32 amount) public {
        lockToken.initialize("LockToken", "LOCK", owner, operator);
        bool transferPassed = lockToken.transfer(accountOne, amount);
        assertTrue(transferPassed);
    }

    function test__transfer_from_tokens_fuzz(uint32 amount) public {
        lockToken.initialize("LockToken", "LOCK", owner, operator);
        lockToken.approve(operator, amount);
        vm.stopPrank();
        vm.prank(operator);
        bool transferPassed = lockToken.transferFrom(owner, accountOne, amount);
        assertTrue(transferPassed);
    }

    function test__cannot_transfer_exceed_amount() public {
        lockToken.initialize("LockToken", "LOCK", owner, operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20InsufficientBalance.selector, owner, lockToken.balanceOf(owner), 6_000_000_001 * 1e18
            )
        );
        lockToken.transfer(accountOne, 6_000_000_001 * 1e18);
    }

    function test__cannot_transfer_from_if_not_approve() public {
        lockToken.initialize("LockToken", "LOCK", owner, operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20InsufficientAllowance.selector, operator, lockToken.allowance(owner, operator), 1000 * 1e18
            )
        );
        vm.stopPrank();
        vm.prank(operator);
        lockToken.transferFrom(owner, accountOne, 1000 * 1e18);
    }
}
