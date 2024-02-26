// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LockToken} from "../contracts/LockToken.sol";
import {Airdrop} from "../contracts/Airdrop.sol";
import {LockonVesting} from "../contracts/LockonVesting.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract AirdropTest is Test {
    Airdrop public airdrop;
    LockToken public lockToken;
    ERC1967Proxy tokenProxy;
    ERC1967Proxy lockonVestingProxy;
    ERC1967Proxy airdropProxy;
    LockonVesting public lockonVesting;
    uint256 constant VALIDATOR_PRIVATE_KEY = 123;
    address public constant OWNER = address(bytes20(bytes("OWNER")));
    address public constant ACCOUNT_ONE = address(1);
    address public constant ACCOUNT_TWO = address(2);
    address public validator = vm.addr(VALIDATOR_PRIVATE_KEY);
    uint256 public constant TEST_ACCOUNT_INITIAL_LOCK_BALANCE = 1000 ether;
    uint256 lockAmount = 1 ether;

    error OwnableUnauthorizedAccount(address account);

    error EnforcedPause();

    function setUp() public {
        vm.startPrank(OWNER);
        bytes memory tokenData = abi.encodeCall(lockToken.initialize, ("LockToken", "LOCK", OWNER, validator));
        lockToken = new LockToken();
        tokenProxy = new ERC1967Proxy(address(lockToken), tokenData);
        lockToken = LockToken(address(tokenProxy));
        lockToken.transfer(ACCOUNT_ONE, TEST_ACCOUNT_INITIAL_LOCK_BALANCE);
        lockToken.transfer(ACCOUNT_TWO, TEST_ACCOUNT_INITIAL_LOCK_BALANCE);
        airdrop = new Airdrop();
        lockonVesting = new LockonVesting();
        bytes memory lockonVestingData = abi.encodeCall(lockonVesting.initialize, (ACCOUNT_ONE, address(lockToken)));
        lockonVestingProxy = new ERC1967Proxy(address(lockonVesting), lockonVestingData);
        lockonVesting = LockonVesting(address(lockonVestingProxy));
        deal(OWNER, 100 ether);
    }

    function initializeAndConfig() public {
        bytes memory airdropData =
            abi.encodeCall(airdrop.initialize, (OWNER, address(lockonVesting), address(lockToken), 0));
        airdropProxy = new ERC1967Proxy(address(airdrop), airdropData);
        airdrop = Airdrop(address(airdropProxy));
        // Transfer lock token to contract for reward distribution
        lockToken.transfer(address(airdrop), 100000 ether);
        vm.stopPrank();
        // Approve to pay reward
        vm.prank(validator);
        lockToken.approve(validator, 100000 ether);
        vm.prank(ACCOUNT_ONE);
        lockonVesting.addAddressDepositPermission(address(airdrop));
    }

    function test_initialize_fail_owner_zero_address() public {
        vm.expectRevert("Airdrop: owner is the zero address");
        bytes memory airdropData =
            abi.encodeCall(airdrop.initialize, (address(0), address(lockonVesting), address(lockToken), 0));
        airdropProxy = new ERC1967Proxy(address(airdrop), airdropData);
        airdrop = Airdrop(address(airdropProxy));
    }

    function test_initialize_fail_lockon_vesting_zero_address() public {
        vm.expectRevert("Airdrop: lockonVesting is the zero address");
        bytes memory airdropData = abi.encodeCall(airdrop.initialize, (OWNER, address(0), address(lockToken), 0));
        airdropProxy = new ERC1967Proxy(address(airdrop), airdropData);
        airdrop = Airdrop(address(airdropProxy));
    }

    function test_initialize_fail_lock_token_zero_address() public {
        vm.expectRevert("Airdrop: lockToken is the zero address");
        bytes memory airdropData = abi.encodeCall(airdrop.initialize, (OWNER, address(lockonVesting), address(0), 0));
        airdropProxy = new ERC1967Proxy(address(airdrop), airdropData);
        airdrop = Airdrop(address(airdropProxy));
    }

    function test_distribute_airdrop_reward() public {
        initializeAndConfig();
        // Using account one
        vm.startPrank(OWNER);
        lockToken.approve(address(airdrop), 1 ether);
        address[] memory listUser = new address[](1300);
        uint256[] memory listAmount = new uint256[](1300);
        for (uint256 i; i < 1300;) {
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
        initializeAndConfig();
        // Using account one
        vm.startPrank(OWNER);
        lockToken.approve(address(airdrop), 1 ether);
        address[] memory listUser = new address[](300);
        uint256[] memory listAmount = new uint256[](300);
        for (uint256 i; i < 300;) {
            uint256 number = i + 3;
            string memory stringNumber = vm.toString(number);
            listUser[i] = address(bytes20(bytes(stringNumber)));
            listAmount[i] = (i + 1) * 10;
            unchecked {
                i++;
            }
        }
        listUser[0] = ACCOUNT_ONE;
        airdrop.distributeAirdropReward(listUser, listAmount);
        lockToken.approve(address(airdrop), 1 ether);
        vm.stopPrank();
        vm.startPrank(ACCOUNT_ONE);
        uint256 gasClaim = gasleft();
        airdrop.claimPendingReward();
        assertEq(airdrop.userPendingReward(listUser[0]), 0);
        gasClaim -= gasleft();
        emit log_named_uint("gasUsedForClaim", gasClaim);
    }

    function test_distribute_airdrop_reward_fail() public {
        initializeAndConfig();
        vm.startPrank(OWNER);
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
        vm.expectRevert("Airdrop: Zero amount is not allowed");
        airdrop.distributeAirdropReward(listUser, listTestAmount);
        listTestAmount[1] = 20;
        listUser[1] = address(0);
        vm.expectRevert("Airdrop: Zero address is not allowed");
        airdrop.distributeAirdropReward(listUser, listTestAmount);
        address[] memory listUserData = new address[](1301);
        uint256[] memory listAmountData = new uint256[](1301);
        for (uint256 i; i < 1301;) {
            uint256 number = i + 3;
            string memory stringNumber = vm.toString(number);
            listUserData[i] = address(bytes20(bytes(stringNumber)));
            listAmountData[i] = (i + 1) * 10;
            unchecked {
                i++;
            }
        }
        vm.expectRevert("Airdrop: Too many addresses");
        airdrop.distributeAirdropReward(listUserData, listAmountData);
    }

    function test_claim_pending_reward_fail() public {
        initializeAndConfig();
        // Using account one
        vm.startPrank(ACCOUNT_ONE);
        vm.expectRevert("Airdrop: User does not have any airdrop reward to claim");
        airdrop.claimPendingReward();
        vm.stopPrank();
        vm.startPrank(OWNER);
        airdrop.setStartTimestamp(1_765_289_065);
        vm.stopPrank();
        vm.startPrank(ACCOUNT_ONE);
        vm.expectRevert("Airdrop: Airdrop not start");
        airdrop.claimPendingReward();
    }

    function test_allocate_token() public {
        initializeAndConfig();
        uint256 oldLockBalance = lockToken.balanceOf(address(airdrop));
        // Using account one
        vm.startPrank(OWNER);
        vm.recordLogs();
        // Allocate amount of lock token
        lockToken.approve(address(airdrop), lockAmount);
        airdrop.allocateLockToken(lockAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[2].topics[0], keccak256("LockTokenAllocated(address,uint256)"));
        assertEq(lockToken.balanceOf(address(airdrop)), oldLockBalance + lockAmount);
    }

    function test_deallocate_token() public {
        initializeAndConfig();
        uint256 oldLockBalance = lockToken.balanceOf(address(airdrop));
        vm.startPrank(OWNER);
        vm.recordLogs();
        // Deallocate amount of LOCK token
        lockToken.approve(address(airdrop), lockAmount * 2);
        airdrop.allocateLockToken(lockAmount * 2);
        lockToken.approve(address(airdrop), lockAmount);
        airdrop.deallocateLockToken(lockAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[5].topics[0], keccak256("LockTokenDeallocated(address,uint256)"));
        assertEq(lockToken.balanceOf(address(airdrop)), oldLockBalance + lockAmount);
    }

    function test_set_lockon_vesting_address() public {
        initializeAndConfig();
        vm.prank(OWNER);
        vm.recordLogs();
        airdrop.setLockonVesting(ACCOUNT_ONE);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(airdrop.lockonVesting(), ACCOUNT_ONE);
        assertEq(entries[0].topics[0], keccak256("LockonVestingUpdated(address,address,uint256)"));
    }

    function test_set_lockon_vesting_address_fail() public {
        initializeAndConfig();
        vm.prank(ACCOUNT_ONE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, ACCOUNT_ONE));
        airdrop.setLockonVesting(ACCOUNT_ONE);
        vm.expectRevert("Airdrop: Zero address not allowed");
        vm.prank(OWNER);
        airdrop.setLockonVesting(address(0));
    }

    function test__add_address_distribute_permission() public {
        initializeAndConfig();
        vm.startPrank(OWNER);
        vm.recordLogs();
        airdrop.addDistributePermission(ACCOUNT_ONE);
        assertEq(airdrop.isAllowedDistribute(ACCOUNT_ONE), true);
        address[] memory listAllowedDistribute = airdrop.getListAllowedDistribute();
        assertEq(listAllowedDistribute[0], ACCOUNT_ONE);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("DistributePermissionStatusUpdated(address,address,bool,uint256)"));
    }

    function test__remove_distribute_permission() public {
        initializeAndConfig();
        vm.startPrank(OWNER);
        vm.recordLogs();
        airdrop.addDistributePermission(ACCOUNT_ONE);
        airdrop.removeDistributePermission(ACCOUNT_ONE);
        airdrop.addDistributePermission(ACCOUNT_ONE);
        assertEq(airdrop.isAllowedDistribute(ACCOUNT_ONE), true);
        address[] memory listAllowedDistribute = airdrop.getListAllowedDistribute();
        assertEq(listAllowedDistribute[0], ACCOUNT_ONE);
        airdrop.removeDistributePermission(ACCOUNT_ONE);
        listAllowedDistribute = airdrop.getListAllowedDistribute();
        assertEq(airdrop.isAllowedDistribute(ACCOUNT_ONE), false);
        assertEq(listAllowedDistribute.length, 0);
        airdrop.addDistributePermission(ACCOUNT_ONE);
        airdrop.addDistributePermission(ACCOUNT_TWO);
        airdrop.removeDistributePermission(ACCOUNT_TWO);
        listAllowedDistribute = airdrop.getListAllowedDistribute();
        assertEq(listAllowedDistribute[0], ACCOUNT_ONE);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("DistributePermissionStatusUpdated(address,address,bool,uint256)"));
        assertEq(entries[1].topics[0], keccak256("DistributePermissionStatusUpdated(address,address,bool,uint256)"));
        assertEq(entries[2].topics[0], keccak256("DistributePermissionStatusUpdated(address,address,bool,uint256)"));
        assertEq(entries[3].topics[0], keccak256("DistributePermissionStatusUpdated(address,address,bool,uint256)"));
    }

    function test__add_and_remove_distribute_permission_fail() public {
        initializeAndConfig();
        vm.startPrank(OWNER);
        airdrop.addDistributePermission(ACCOUNT_ONE);
        vm.expectRevert("Airdrop: Zero address not allowed");
        airdrop.addDistributePermission(address(0));
        vm.expectRevert("Airdrop: List allowed distribute address already contains this address");
        airdrop.addDistributePermission(ACCOUNT_ONE);
        vm.expectRevert("Airdrop: Zero address not allowed");
        airdrop.removeDistributePermission(address(0));
        vm.expectRevert("Airdrop: List allowed distribute address does not contain this address");
        airdrop.removeDistributePermission(ACCOUNT_TWO);
    }

    function test_set_functions() public {
        initializeAndConfig();
        vm.startPrank(OWNER);
        vm.recordLogs();
        airdrop.setStartTimestamp(2000);
        assertEq(airdrop.startTimestamp(), 2000);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("StartTimestampUpdated(address,uint256,uint256)"));
    }

    function test_pause_and_unpause() public {
        initializeAndConfig();
        vm.startPrank(OWNER);
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
        vm.startPrank(ACCOUNT_ONE);
        vm.expectRevert(EnforcedPause.selector);
        airdrop.claimPendingReward();
        vm.stopPrank();
        // Transaction can be executed normal when unpause
        vm.startPrank(OWNER);
        airdrop.unPause();
        lockToken.approve(address(airdrop), amount);
        airdrop.distributeAirdropReward(listUser, listAmount);
        assertEq(airdrop.userPendingReward(listUser[0]), 40);
        assertEq(airdrop.userPendingReward(listUser[1]), 30);
    }
}
