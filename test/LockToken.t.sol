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
    address public MANAGEMENT = address(bytes20(bytes("MANAGEMENT")));
    address public ACCOUNT_ONE = address(1);
    address public ACCOUNT_TWO = address(2);
    address public ACCOUNT_THREE = address(3);

    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    // Events from LockToken contract
    event UserBlacklistAdded(address indexed sender, address indexed userAddress, uint256 timestamp);
    event UserBlacklistRemoved(address indexed sender, address indexed userAddress, uint256 timestamp);

    function setUp() public {
        vm.startPrank(OWNER);
        lockToken = new LockToken();
    }

    function initializeAndConfig() public {
        bytes memory tokenData = abi.encodeCall(lockToken.initialize, ("LockToken", "LOCK", OWNER, MANAGEMENT));
        tokenProxy = new ERC1967Proxy(address(lockToken), tokenData);
        lockToken = LockToken(address(tokenProxy));
    }

    function test__initialize_fail_owner_address() public {
        vm.expectRevert("LockToken: ownerAddress is the zero address");
        bytes memory tokenData = abi.encodeCall(lockToken.initialize, ("LockToken", "LOCK", address(0), MANAGEMENT));
        tokenProxy = new ERC1967Proxy(address(lockToken), tokenData);
        lockToken = LockToken(address(tokenProxy));
    }

    function test__initialize_fail_management_address() public {
        vm.expectRevert("LockToken: managementAddress is the zero address");
        bytes memory tokenData = abi.encodeCall(lockToken.initialize, ("LockToken", "LOCK", OWNER, address(0)));
        tokenProxy = new ERC1967Proxy(address(lockToken), tokenData);
        lockToken = LockToken(address(tokenProxy));
    }

    function test__initilize_and_mint_succeed() public {
        initializeAndConfig();
        uint256 ownerBalance = lockToken.balanceOf(OWNER);
        uint256 managementBalance = lockToken.balanceOf(MANAGEMENT);
        assertEq(ownerBalance, 4_000_000_000 * 1e18);
        assertEq(managementBalance, 6_000_000_000 * 1e18);
    }

    function test__transfer_tokens_fuzz(uint32 amount) public {
        initializeAndConfig();
        bool transferPassed = lockToken.transfer(ACCOUNT_ONE, amount);
        assertTrue(transferPassed);
    }

    function test__transfer_from_tokens_fuzz(uint32 amount) public {
        initializeAndConfig();
        lockToken.approve(MANAGEMENT, amount);
        vm.stopPrank();
        vm.startPrank(MANAGEMENT);
        bool transferPassed = lockToken.transferFrom(OWNER, ACCOUNT_ONE, amount);
        assertTrue(transferPassed);
    }

    function test__cannot_transfer_exceed_amount() public {
        initializeAndConfig();
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20InsufficientBalance.selector, OWNER, lockToken.balanceOf(OWNER), 4_000_000_001 * 1e18
            )
        );
        lockToken.transfer(ACCOUNT_ONE, 4_000_000_001 * 1e18);
    }

    function test__cannot_transfer_from_if_not_approve() public {
        initializeAndConfig();
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20InsufficientAllowance.selector, MANAGEMENT, lockToken.allowance(OWNER, MANAGEMENT), 1000 * 1e18
            )
        );
        vm.stopPrank();
        vm.startPrank(MANAGEMENT);
        lockToken.transferFrom(msg.sender, ACCOUNT_ONE, 1000 * 1e18);
    }

    function test__blacklist_add_operations() public {
        initializeAndConfig();

        // Add to blacklist with event check
        vm.expectEmit(true, true, false, true, address(lockToken));
        emit UserBlacklistAdded(OWNER, ACCOUNT_ONE, block.timestamp);
        lockToken.addBlacklistUser(ACCOUNT_ONE);
        assertTrue(lockToken.isBlacklisted(ACCOUNT_ONE));

        // Cannot add zero address
        vm.expectRevert("LOCK Token: Zero address not allowed");
        lockToken.addBlacklistUser(address(0));

        // Cannot add already blacklisted
        vm.expectRevert("LOCK Token: Blacklist already contains this address");
        lockToken.addBlacklistUser(ACCOUNT_ONE);

        // Non-owner cannot add
        vm.stopPrank();
        vm.startPrank(MANAGEMENT);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), MANAGEMENT));
        lockToken.addBlacklistUser(ACCOUNT_TWO);
    }

    function test__blacklist_remove_operations() public {
        initializeAndConfig();
        lockToken.addBlacklistUser(ACCOUNT_ONE);

        // Remove with event check
        vm.expectEmit(true, true, false, true, address(lockToken));
        emit UserBlacklistRemoved(OWNER, ACCOUNT_ONE, block.timestamp);
        lockToken.removeBlacklistUser(ACCOUNT_ONE);
        assertFalse(lockToken.isBlacklisted(ACCOUNT_ONE));

        // Cannot remove zero address
        vm.expectRevert("LOCK Token: Zero address not allowed");
        lockToken.removeBlacklistUser(address(0));

        // Cannot remove non-blacklisted
        vm.expectRevert("LOCK Token: Blacklist does not contain this address");
        lockToken.removeBlacklistUser(ACCOUNT_TWO);

        // Non-owner cannot remove
        lockToken.addBlacklistUser(ACCOUNT_TWO);
        vm.stopPrank();
        vm.startPrank(MANAGEMENT);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), MANAGEMENT));
        lockToken.removeBlacklistUser(ACCOUNT_TWO);
    }

    function test__blacklist_transfer_restrictions() public {
        initializeAndConfig();

        // Test sender blacklisted
        lockToken.addBlacklistUser(OWNER);
        vm.expectRevert("LOCK Token: sender is blocked");
        lockToken.transfer(ACCOUNT_ONE, 100 * 1e18);

        // Reset and test recipient blacklisted
        lockToken.removeBlacklistUser(OWNER);
        lockToken.addBlacklistUser(ACCOUNT_ONE);
        vm.expectRevert("LOCK Token: transfer to is blocked");
        lockToken.transfer(ACCOUNT_ONE, 100 * 1e18);

        // Transfer works after removal from blacklist
        lockToken.removeBlacklistUser(ACCOUNT_ONE);
        bool transferPassed = lockToken.transfer(ACCOUNT_ONE, 100 * 1e18);
        assertTrue(transferPassed);
    }

    function test__blacklist_transferFrom_restrictions() public {
        initializeAndConfig();
        lockToken.approve(MANAGEMENT, type(uint256).max);

        // Test sender blacklisted
        lockToken.addBlacklistUser(MANAGEMENT);
        vm.stopPrank();
        vm.startPrank(MANAGEMENT);
        vm.expectRevert("LOCK Token: sender is blocked");
        lockToken.transferFrom(OWNER, ACCOUNT_ONE, 100 * 1e18);

        // Reset and test owner blacklisted
        vm.stopPrank();
        vm.startPrank(OWNER);
        lockToken.removeBlacklistUser(MANAGEMENT);
        lockToken.addBlacklistUser(OWNER);
        vm.stopPrank();
        vm.startPrank(MANAGEMENT);
        vm.expectRevert("LOCK Token: transfer from is blocked");
        lockToken.transferFrom(OWNER, ACCOUNT_ONE, 100 * 1e18);

        // Reset and test recipient blacklisted
        vm.stopPrank();
        vm.startPrank(OWNER);
        lockToken.removeBlacklistUser(OWNER);
        lockToken.addBlacklistUser(ACCOUNT_ONE);
        vm.stopPrank();
        vm.startPrank(MANAGEMENT);
        vm.expectRevert("LOCK Token: transfer to is blocked");
        lockToken.transferFrom(OWNER, ACCOUNT_ONE, 100 * 1e18);

        // Works after removal
        vm.stopPrank();
        vm.startPrank(OWNER);
        lockToken.removeBlacklistUser(ACCOUNT_ONE);
        vm.stopPrank();
        vm.startPrank(MANAGEMENT);
        bool transferPassed = lockToken.transferFrom(OWNER, ACCOUNT_ONE, 100 * 1e18);
        assertTrue(transferPassed);
    }

    function test__blacklist_approve_restrictions() public {
        initializeAndConfig();

        // Test owner blacklisted
        lockToken.addBlacklistUser(OWNER);
        vm.expectRevert("LOCK Token: owner is blocked");
        lockToken.approve(MANAGEMENT, 100 * 1e18);

        // Test spender blacklisted
        lockToken.removeBlacklistUser(OWNER);
        lockToken.addBlacklistUser(MANAGEMENT);
        vm.expectRevert("LOCK Token: spender is blocked");
        lockToken.approve(MANAGEMENT, 100 * 1e18);

        // Works after removal
        lockToken.removeBlacklistUser(MANAGEMENT);
        bool approvePassed = lockToken.approve(MANAGEMENT, 100 * 1e18);
        assertTrue(approvePassed);
        assertEq(lockToken.allowance(OWNER, MANAGEMENT), 100 * 1e18);
    }

    function test__blacklist_complex_scenarios() public {
        initializeAndConfig();

        // Multiple addresses management
        lockToken.addBlacklistUser(ACCOUNT_ONE);
        lockToken.addBlacklistUser(ACCOUNT_TWO);
        lockToken.addBlacklistUser(ACCOUNT_THREE);

        assertTrue(lockToken.isBlacklisted(ACCOUNT_ONE));
        assertTrue(lockToken.isBlacklisted(ACCOUNT_TWO));
        assertTrue(lockToken.isBlacklisted(ACCOUNT_THREE));

        lockToken.removeBlacklistUser(ACCOUNT_TWO);
        assertFalse(lockToken.isBlacklisted(ACCOUNT_TWO));

        // Owner can remove themselves from blacklist
        lockToken.addBlacklistUser(OWNER);
        lockToken.removeBlacklistUser(OWNER);
        assertFalse(lockToken.isBlacklisted(OWNER));

        // Transfer between non-blacklisted accounts
        lockToken.transfer(ACCOUNT_TWO, 1000 * 1e18);
        vm.stopPrank();
        vm.startPrank(ACCOUNT_TWO);
        vm.expectRevert("LOCK Token: transfer to is blocked");
        lockToken.transfer(ACCOUNT_THREE, 100 * 1e18);
    }
}
