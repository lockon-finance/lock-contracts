// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LockToken} from "../contracts/LockToken.sol";
import {Airdrop} from "../contracts/Airdrop.sol";
import {LockonVesting} from "../contracts/LockonVesting.sol";

contract AirdropTest is Test {
    Airdrop public airdrop;
    LockToken public lockToken;
    LockonVesting public lockonVesting;
    uint256 constant validatorPrivateKey = 123;
    address public constant owner = address(bytes20(bytes("owner")));
    address public constant accountOne = address(1);
    address public constant accountTwo = address(2);
    address public validator = vm.addr(validatorPrivateKey);
    uint256 public constant testAccountInitialLockBalance = 1000 ether;
    uint256 lockAmount = 1 ether;

    error OwnableUnauthorizedAccount(address account);

    error EnforcedPause();

    function setUp() public {
        vm.startPrank(owner);
        lockToken = new LockToken();
        lockToken.initialize("LockToken", "LOCK", owner, validator);
        lockToken.transfer(accountOne, testAccountInitialLockBalance);
        lockToken.transfer(accountTwo, testAccountInitialLockBalance);
        airdrop = new Airdrop();
        lockonVesting = new LockonVesting();
        deal(owner, 100 ether);
    }

    function initilizeAndConfig() public {
        lockonVesting.initialize(accountOne, address(lockToken));
        airdrop.initialize(owner, address(lockonVesting), address(lockToken), 0);
        // Transfer lock token to contract for reward distribution
        lockToken.transfer(address(airdrop), 100000 ether);
        vm.stopPrank();
        // Approve to pay reward
        vm.prank(validator);
        lockToken.approve(address(validator), 100000 ether);
        vm.prank(accountOne);
        lockonVesting.addAddressDepositPermission(address(airdrop));
    }

    function test_distribute_airdrop_reward() public {
        initilizeAndConfig();
        // Using account one
        vm.startPrank(owner);
        lockToken.approve(address(airdrop), 1 ether);
        address[] memory listUser = new address[](1300);
        uint256[] memory listAmount = new uint256[](1300);
        for (uint256 i = 0; i < 1300;) {
            uint256 number = i + 3;
            string memory stringNumber = vm.toString(number);
            listUser[i] = address(bytes20(bytes(stringNumber)));
            listAmount[i] = (i + 1) * 10;
            unchecked {
                i++;
            }
        }
        vm.recordLogs();
        uint256 gas = gasleft();
        airdrop.distributeAirdropReward(listUser, listAmount);
        gas -= gasleft();
        emit log_named_uint("gasUsedForDistributed", gas);
        assertEq(airdrop.userPendingReward(listUser[0]), listAmount[0]);
        assertEq(airdrop.userPendingReward(listUser[1]), 20);
        assertEq(airdrop.totalPendingAirdropAmount(), 8456500);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("AirdropRewardDistributed(address,uint256,uint256)"));
    }

    function test_claim_pending_reward() public {
        initilizeAndConfig();
        // Using account one
        vm.startPrank(owner);
        lockToken.approve(address(airdrop), 1 ether);
        address[] memory listUser = new address[](300);
        uint256[] memory listAmount = new uint256[](300);
        for (uint256 i = 0; i < 300;) {
            uint256 number = i + 3;
            string memory stringNumber = vm.toString(number);
            listUser[i] = address(bytes20(bytes(stringNumber)));
            listAmount[i] = (i + 1) * 10;
            unchecked {
                i++;
            }
        }
        listUser[0] = address(accountOne);
        airdrop.distributeAirdropReward(listUser, listAmount);
        lockToken.approve(address(airdrop), 1 ether);
        vm.stopPrank();
        vm.startPrank(accountOne);
        uint256 gasClaim = gasleft();
        airdrop.claimPendingReward();
        assertEq(airdrop.userPendingReward(listUser[0]), 0);
        gasClaim -= gasleft();
        emit log_named_uint("gasUsedForClaim", gasClaim);
    }

    function test_distribute_airdrop_reward_fail() public {
        initilizeAndConfig();
        vm.startPrank(owner);
        lockToken.approve(address(airdrop), 1 ether);
        address[] memory listUser = new address[](2);
        uint256[] memory listAmount = new uint256[](1);
        listUser[0] = address(bytes20(bytes("4")));
        listUser[1] = address(bytes20(bytes("5")));
        listAmount[0] = 40;
        vm.expectRevert("Airdrop: The list for user address and amount value must have equal length");
        airdrop.distributeAirdropReward(listUser, listAmount);
        uint256[] memory listTestAmount = new uint256[](2);
        listTestAmount[0] = 40;
        listTestAmount[1] = 0;
        vm.expectRevert("Airdrop: Zero address or zero amount is not allowed");
        airdrop.distributeAirdropReward(listUser, listTestAmount);
    }

    function test_claim_pending_reward_fail() public {
        initilizeAndConfig();
        // Using account one
        vm.startPrank(accountOne);
        vm.expectRevert("Airdrop: User does not have any airdrop reward to claim");
        airdrop.claimPendingReward();
        vm.stopPrank();
        vm.startPrank(owner);
        airdrop.setStartTimestamp(1765289065);
        vm.stopPrank();
        vm.startPrank(accountOne);
        vm.expectRevert("Airdrop: Airdrop not start");
        airdrop.claimPendingReward();
    }

    function test_allocate_token() public {
        initilizeAndConfig();
        uint256 oldLockBalance = lockToken.balanceOf(address(airdrop));
        // Using account one
        vm.startPrank(owner);
        vm.recordLogs();
        // Allocate amount of lock token
        lockToken.approve(address(airdrop), lockAmount);
        airdrop.allocateLockToken(lockAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[2].topics[0], keccak256("LockTokenAllocated(address,uint256)"));
        assertEq(lockToken.balanceOf(address(airdrop)), oldLockBalance + lockAmount);
    }

    function test_deallocate_token() public {
        initilizeAndConfig();
        uint256 oldLockBalance = lockToken.balanceOf(address(airdrop));
        // Using account one
        vm.startPrank(owner);
        vm.recordLogs();
        // Deallocate amount of LOCK token
        lockToken.approve(address(airdrop), lockAmount);
        airdrop.deallocateLockToken(lockAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[2].topics[0], keccak256("LockTokenDeallocated(address,uint256)"));
        assertEq(lockToken.balanceOf(address(airdrop)), oldLockBalance - lockAmount);
    }

    function test_set_lockon_vesting_address() public {
        initilizeAndConfig();
        vm.prank(owner);
        vm.recordLogs();
        airdrop.setLockonVesting(accountOne);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(airdrop.lockonVesting(), accountOne);
        assertEq(entries[0].topics[0], keccak256("LockonVestingUpdated(address,uint256)"));
    }

    function test_set_lockon_vesting_address_fail() public {
        initilizeAndConfig();
        vm.prank(accountOne);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, accountOne));
        airdrop.setLockonVesting(accountOne);
        vm.expectRevert("Airdrop: Zero address not allowed");
        vm.prank(owner);
        airdrop.setLockonVesting(address(0));
    }

    function test__add_address_distribute_permission() public {
        initilizeAndConfig();
        vm.startPrank(owner);
        vm.recordLogs();
        airdrop.addDistributePermission(accountOne);
        assertEq(airdrop.isAllowedDistribute(accountOne), true);
        address[] memory listAllowedDistribute = airdrop.getListAllowedDistribute();
        assertEq(listAllowedDistribute[0], accountOne);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("DistributePermissionStatusUpdated(address,bool,uint256)"));
    }

    function test__remove_distribute_permission() public {
        initilizeAndConfig();
        vm.startPrank(owner);
        vm.recordLogs();
        airdrop.addDistributePermission(accountOne);
        airdrop.removeDistributePermission(accountOne);
        airdrop.addDistributePermission(accountOne);
        assertEq(airdrop.isAllowedDistribute(accountOne), true);
        address[] memory listAllowedDistribute = airdrop.getListAllowedDistribute();
        assertEq(listAllowedDistribute[0], accountOne);
        airdrop.removeDistributePermission(accountOne);
        listAllowedDistribute = airdrop.getListAllowedDistribute();
        assertEq(airdrop.isAllowedDistribute(accountOne), false);
        assertEq(listAllowedDistribute.length, 0);
        airdrop.addDistributePermission(accountOne);
        airdrop.addDistributePermission(accountTwo);
        airdrop.removeDistributePermission(accountTwo);
        listAllowedDistribute = airdrop.getListAllowedDistribute();
        assertEq(listAllowedDistribute[0], accountOne);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("DistributePermissionStatusUpdated(address,bool,uint256)"));
        assertEq(entries[1].topics[0], keccak256("DistributePermissionStatusUpdated(address,bool,uint256)"));
        assertEq(entries[2].topics[0], keccak256("DistributePermissionStatusUpdated(address,bool,uint256)"));
        assertEq(entries[3].topics[0], keccak256("DistributePermissionStatusUpdated(address,bool,uint256)"));
    }

    function test__add_and_remove_distribute_permission_fail() public {
        initilizeAndConfig();
        vm.startPrank(owner);
        airdrop.addDistributePermission(accountOne);
        vm.expectRevert("Airdrop: Zero address not allowed");
        airdrop.addDistributePermission(address(0));
        vm.expectRevert("Airdrop: List allowed distribute address already contains this address");
        airdrop.addDistributePermission(accountOne);
        vm.expectRevert("Airdrop: Zero address not allowed");
        airdrop.removeDistributePermission(address(0));
        vm.expectRevert("Airdrop: List allowed distribute address does not contain this address");
        airdrop.removeDistributePermission(accountTwo);
    }

    function test_set_functions() public {
        initilizeAndConfig();
        vm.startPrank(owner);
        vm.recordLogs();
        airdrop.setStartTimestamp(2000);
        assertEq(airdrop.startTimestamp(), 2000);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("StartTimestampUpdated(uint256,uint256)"));
    }

    function test_pause_and_unpause() public {
        initilizeAndConfig();
        vm.startPrank(owner);
        airdrop.pause();
        // Cannot do any action when contract is paused
        uint256 amount = 1 ether;
        address[] memory listUser = new address[](2);
        uint256[] memory listAmount = new uint256[](2);
        listUser[0] = address(bytes20(bytes("4")));
        listUser[1] = address(bytes20(bytes("5")));
        listAmount[0] = 40;
        listAmount[1] = 30;
        vm.expectRevert(EnforcedPause.selector);
        airdrop.distributeAirdropReward(listUser, listAmount);
        vm.stopPrank();
        vm.startPrank(accountOne);
        vm.expectRevert(EnforcedPause.selector);
        airdrop.claimPendingReward();
        vm.stopPrank();
        // Transaction can be executed normal when unpause
        vm.startPrank(owner);
        airdrop.unPause();
        lockToken.approve(address(airdrop), amount);
        airdrop.distributeAirdropReward(listUser, listAmount);
        assertEq(airdrop.userPendingReward(listUser[0]), 40);
        assertEq(airdrop.userPendingReward(listUser[1]), 30);
    }
}
