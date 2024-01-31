// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LockToken} from "../contracts/LockToken.sol";
import {MerkleAirdrop} from "../contracts/MerkleAirdrop.sol";
import {LockonVesting} from "../contracts/LockonVesting.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MerkleAirdropTest is Test {
    MerkleAirdrop public merkleAirdrop;
    LockToken public lockToken;
    LockonVesting public lockonVesting;
    ERC1967Proxy tokenProxy;
    ERC1967Proxy lockonVestingProxy;
    ERC1967Proxy merkleAirdropProxy;
    uint256 constant VALIDATOR_PRIVATE_KEY = 123;
    address public constant OWNER = address(bytes20(bytes("OWNER")));
    address public constant ACCOUNT_ONE = address(1);
    address public VALIDATOR = vm.addr(VALIDATOR_PRIVATE_KEY);
    uint256 public constant TEST_ACCOUNT_INITIAL_LOCK_BALANCE = 1000 ether;
    uint256 lockAmount = 1 ether;
    bytes32 public root;
    address public user;

    error OwnableUnauthorizedAccount(address account);

    error EnforcedPause();

    function setUp() public {
        vm.startPrank(OWNER);
        bytes memory tokenData = abi.encodeCall(lockToken.initialize, ("LockToken", "LOCK", OWNER, VALIDATOR));
        lockToken = new LockToken();
        tokenProxy = new ERC1967Proxy(address(lockToken), tokenData);
        lockToken = LockToken(address(tokenProxy));
        lockToken.transfer(ACCOUNT_ONE, TEST_ACCOUNT_INITIAL_LOCK_BALANCE);
        merkleAirdrop = new MerkleAirdrop();
        lockonVesting = new LockonVesting();
        deal(OWNER, 100 ether);
        // Root and user value are retrieved from test-output.json
        root = 0x94d7b8d37a07dc816d7d72922a0eb0d8d38caf144cc3e37c176cfbdb15aeb34a;
        user = 0x500965396618E44200FD960bCB0a0675DbA2A778;
    }

    function initializeAndConfig() public {
        bytes memory lockonVestingData = abi.encodeCall(lockonVesting.initialize, (ACCOUNT_ONE, address(lockToken)));
        lockonVestingProxy = new ERC1967Proxy(address(lockonVesting), lockonVestingData);
        lockonVesting = LockonVesting(address(lockonVestingProxy));
        bytes memory merkleAirdropData =
            abi.encodeCall(merkleAirdrop.initialize, (OWNER, address(lockonVesting), address(lockToken), root, 0));
        merkleAirdropProxy = new ERC1967Proxy(address(merkleAirdrop), merkleAirdropData);
        merkleAirdrop = MerkleAirdrop(address(merkleAirdropProxy));
        // Transfer lock token to contract for reward distribution
        lockToken.transfer(address(merkleAirdrop), 100000 ether);
        vm.stopPrank();
        // Approve to pay reward
        vm.prank(VALIDATOR);
        lockToken.approve(VALIDATOR, 100000 ether);
        vm.prank(ACCOUNT_ONE);
        lockonVesting.addAddressDepositPermission(address(merkleAirdrop));
    }

    function test_claim_pending_reward_multiple_addresses() public {
        initializeAndConfig();
        vm.startPrank(OWNER);
        lockToken.approve(address(merkleAirdrop), 1 ether);
        vm.stopPrank();
        vm.startPrank(user);
        // Get proof from test-output.json
        bytes32[] memory proof = new bytes32[](5);
        proof[0] = 0xa72aaf5b2933c894bedbc6f7ffb0b83c5c09877ff38c366769acca7399ec0bc9;
        proof[1] = 0x38e30df43e79aafb79a2fb0e9936afe068cad27a65af5445244264eaaca2a6e1;
        proof[2] = 0x22fba420378ad5f74fb15a1413b81458b3c639a7e95ba05e71b1287fea9671af;
        proof[3] = 0xf44859431420ef662dfc5dbc2c4d73c9db2ac925a3ac04695d54d4fa220423d2;
        proof[4] = 0xa80c6155781dda72531a679b4a2c84122f6fbb1cf9c9aaefcea2ffbabdecac7f;
        merkleAirdrop.claimPendingReward(10, proof);
        (, uint256 userVestingAmount,,,,) = lockonVesting.userVestingWallet(user, 2);
        assertEq(userVestingAmount, 10);
    }

    function test_claim_pending_reward_fail() public {
        initializeAndConfig();
        // Get proof from test-output.json
        bytes32[] memory proof = new bytes32[](5);
        proof[0] = 0xa72aaf5b2933c894bedbc6f7ffb0b83c5c09877ff38c366769acca7399ec0bc9;
        proof[1] = 0x38e30df43e79aafb79a2fb0e9936afe068cad27a65af5445244264eaaca2a6e1;
        proof[2] = 0x22fba420378ad5f74fb15a1413b81458b3c639a7e95ba05e71b1287fea9671af;
        proof[3] = 0xf44859431420ef662dfc5dbc2c4d73c9db2ac925a3ac04695d54d4fa220423d2;
        proof[4] = 0xa80c6155781dda72531a679b4a2c84122f6fbb1cf9c9aaefcea2ffbabdecac7f;
        vm.startPrank(OWNER);
        merkleAirdrop.setStartTimestamp(17655);
        vm.stopPrank();
        vm.startPrank(user);
        vm.expectRevert("Airdrop: Airdrop not start");
        merkleAirdrop.claimPendingReward(10, proof);
        vm.stopPrank();
        vm.startPrank(OWNER);
        merkleAirdrop.setStartTimestamp(0);
        vm.stopPrank();
        vm.startPrank(user);
        proof[0] = 0xa72aaf5b2933c894bedbc6f7ffb0b83c5c09877ff38c366769acca7399ec0bf3;
        vm.expectRevert("Airdrop: Invalid proof");
        merkleAirdrop.claimPendingReward(10, proof);
        proof[0] = 0xa72aaf5b2933c894bedbc6f7ffb0b83c5c09877ff38c366769acca7399ec0bc9;
        merkleAirdrop.claimPendingReward(10, proof);
        vm.expectRevert("Airdrop: User has already claimed this reward");
        merkleAirdrop.claimPendingReward(10, proof);
    }

    function test_allocate_token() public {
        initializeAndConfig();
        uint256 oldLockBalance = lockToken.balanceOf(address(merkleAirdrop));
        // Using account one
        vm.startPrank(OWNER);
        vm.recordLogs();
        // Allocate amount of lock token
        lockToken.approve(address(merkleAirdrop), lockAmount);
        merkleAirdrop.allocateLockToken(lockAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[2].topics[0], keccak256("LockTokenAllocated(address,uint256)"));
        assertEq(lockToken.balanceOf(address(merkleAirdrop)), oldLockBalance + lockAmount);
    }

    function test_deallocate_token() public {
        initializeAndConfig();
        uint256 oldLockBalance = lockToken.balanceOf(address(merkleAirdrop));
        // Using account one
        vm.startPrank(OWNER);
        vm.recordLogs();
        // Deallocate amount of LOCK token
        lockToken.approve(address(merkleAirdrop), lockAmount);
        merkleAirdrop.deallocateLockToken(lockAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[2].topics[0], keccak256("LockTokenDeallocated(address,uint256)"));
        assertEq(lockToken.balanceOf(address(merkleAirdrop)), oldLockBalance - lockAmount);
    }

    function test_set_lockon_vesting_address() public {
        initializeAndConfig();
        vm.prank(OWNER);
        vm.recordLogs();
        merkleAirdrop.setLockonVesting(ACCOUNT_ONE);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(merkleAirdrop.lockonVesting(), ACCOUNT_ONE);
        assertEq(entries[0].topics[0], keccak256("LockonVestingUpdated(address,address,uint256)"));
    }

    function test_set_lockon_vesting_address_fail() public {
        initializeAndConfig();
        vm.prank(ACCOUNT_ONE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, ACCOUNT_ONE));
        merkleAirdrop.setLockonVesting(ACCOUNT_ONE);
        vm.expectRevert("Airdrop: Zero address not allowed");
        vm.prank(OWNER);
        merkleAirdrop.setLockonVesting(address(0));
    }

    function test_set_functions() public {
        initializeAndConfig();
        vm.startPrank(OWNER);
        vm.recordLogs();
        merkleAirdrop.setMerkleRoot(0xb47986d5cfa18f2a51a517e4e85b9ae8c5ba7e5fc2a73feecfd38954aad6a2e4);
        assertEq(merkleAirdrop.merkleRoot(), 0xb47986d5cfa18f2a51a517e4e85b9ae8c5ba7e5fc2a73feecfd38954aad6a2e4);
        merkleAirdrop.setStartTimestamp(2000);
        assertEq(merkleAirdrop.startTimestamp(), 2000);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("MerkleRootUpdated(address,bytes32,uint256)"));
        assertEq(entries[1].topics[0], keccak256("StartTimestampUpdated(address,uint256,uint256)"));
    }

    function test_pause_and_unpause() public {
        initializeAndConfig();
        vm.startPrank(OWNER);
        merkleAirdrop.pause();
        // Cannot do any action when contract is paused
        uint256 amount = 1 ether;
        vm.stopPrank();
        vm.startPrank(user);
        // Get proof from test-output.json
        bytes32[] memory proof = new bytes32[](5);
        proof[0] = 0xa72aaf5b2933c894bedbc6f7ffb0b83c5c09877ff38c366769acca7399ec0bc9;
        proof[1] = 0x38e30df43e79aafb79a2fb0e9936afe068cad27a65af5445244264eaaca2a6e1;
        proof[2] = 0x22fba420378ad5f74fb15a1413b81458b3c639a7e95ba05e71b1287fea9671af;
        proof[3] = 0xf44859431420ef662dfc5dbc2c4d73c9db2ac925a3ac04695d54d4fa220423d2;
        proof[4] = 0xa80c6155781dda72531a679b4a2c84122f6fbb1cf9c9aaefcea2ffbabdecac7f;
        vm.expectRevert(EnforcedPause.selector);
        merkleAirdrop.claimPendingReward(10, proof);
        vm.stopPrank();
        // Transaction can be executed normal when unpause
        vm.startPrank(OWNER);
        merkleAirdrop.unPause();
        lockToken.approve(address(merkleAirdrop), amount);
        vm.stopPrank();
        vm.startPrank(user);
        merkleAirdrop.claimPendingReward(10, proof);
    }
}
