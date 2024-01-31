// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {LockToken} from "../contracts/LockToken.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract LockTokenTest is Test {
    LockToken public lockToken;
    ERC1967Proxy tokenProxy;
    address public OWNER = address(bytes20(bytes("OWNER")));
    address public OPERATOR = address(bytes20(bytes("OPERATOR")));
    address public ACCOUNT_ONE = address(1);

    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    function setUp() public {
        vm.startPrank(OWNER);
        lockToken = new LockToken();
    }

    function initializeAndConfig() public {
        bytes memory tokenData = abi.encodeCall(lockToken.initialize, ("LockToken", "LOCK", OWNER, OPERATOR));
        tokenProxy = new ERC1967Proxy(address(lockToken), tokenData);
        lockToken = LockToken(address(tokenProxy));
    }

    function test__initilize_and_mint_succeed() public {
        initializeAndConfig();
        uint256 ownerBalance = lockToken.balanceOf(OWNER);
        uint256 operatorBalance = lockToken.balanceOf(OPERATOR);
        assertEq(ownerBalance, 6_000_000_000 * 1e18);
        assertEq(operatorBalance, 4_000_000_000 * 1e18);
    }

    function test__transfer_tokens_fuzz(uint32 amount) public {
        initializeAndConfig();
        bool transferPassed = lockToken.transfer(ACCOUNT_ONE, amount);
        assertTrue(transferPassed);
    }

    function test__transfer_from_tokens_fuzz(uint32 amount) public {
        initializeAndConfig();
        lockToken.approve(OPERATOR, amount);
        vm.stopPrank();
        vm.startPrank(OPERATOR);
        bool transferPassed = lockToken.transferFrom(OWNER, ACCOUNT_ONE, amount);
        assertTrue(transferPassed);
    }

    function test__cannot_transfer_exceed_amount() public {
        initializeAndConfig();
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20InsufficientBalance.selector, OWNER, lockToken.balanceOf(OWNER), 6_000_000_001 * 1e18
            )
        );
        lockToken.transfer(ACCOUNT_ONE, 6_000_000_001 * 1e18);
    }

    function test__cannot_transfer_from_if_not_approve() public {
        initializeAndConfig();
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20InsufficientAllowance.selector, OPERATOR, lockToken.allowance(OWNER, OPERATOR), 1000 * 1e18
            )
        );
        vm.stopPrank();
        vm.startPrank(OPERATOR);
        lockToken.transferFrom(msg.sender, ACCOUNT_ONE, 1000 * 1e18);
    }
}
