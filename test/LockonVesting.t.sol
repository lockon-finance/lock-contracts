// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {LockToken} from "../contracts/LockToken.sol";
import {LockonVesting} from "../contracts/LockonVesting.sol";
import "../contracts/interfaces/ILockonVesting.sol";

contract LockonVestingTest is Test {
    LockonVesting public lockonVesting;
    LockToken public lockToken;
    address public constant owner = address(bytes20(bytes("owner")));
    address public constant accountOne = address(1);
    address public constant accountTwo = address(2);

    error OwnableUnauthorizedAccount(address account);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error EnforcedPause();

    function setUp() public {
        vm.startPrank(owner);
        lockToken = new LockToken();
        lockToken.initialize("LockToken", "LOCK", owner, accountOne);
        lockonVesting = new LockonVesting();
        deal(owner, 100 ether);
    }

    function initilizeVestingContract() public {
        lockonVesting.initialize(owner, address(lockToken));
    }

    function deposit(address user, uint256 _amount, uint256 categoryId) public {
        lockToken.approve(address(lockonVesting), _amount);
        lockonVesting.deposit(user, _amount, categoryId);
    }

    function test__owner_add_vesting_wallet() public {
        initilizeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        lockToken.approve(address(lockonVesting), vestingAmount);
        vm.recordLogs();
        lockonVesting.deposit(accountOne, vestingAmount, 0); // Vesting for 60 seconds
        Vm.Log[] memory entries = vm.getRecordedLogs();
        /**
         * Make sure that event add is emitted
         *
         * @dev Get the entries at index 1 since on add vesting function call,
         * event transfer from also get emitted at index 0, enum convert to uint
         */
        assertEq(entries[1].topics[0], keccak256("VestingDeposited(address,address,uint256,uint256,uint256,uint256)"));
    }

    function test__deposit_fail() public {
        initilizeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        // Only owner check
        vm.stopPrank();
        vm.prank(accountOne);
        vm.expectRevert("LOCKON Vesting: Forbidden");
        lockonVesting.deposit(accountOne, vestingAmount, 0);
        // Not enough allowance check
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20InsufficientAllowance.selector,
                address(lockonVesting),
                lockToken.allowance(owner, address(lockonVesting)),
                vestingAmount
            )
        );
        vm.startPrank(owner);
        lockonVesting.deposit(accountTwo, vestingAmount, 0);
        // Add vesting for blacklist address
        lockonVesting.addBlacklistUser(accountTwo);
        vm.expectRevert("LOCKON Vesting: User has been banned from all activities in LOCKON Vesting");
        lockonVesting.deposit(accountTwo, vestingAmount, 0);
        // Add vesting for zero address
        vm.expectRevert("LOCKON Vesting: Zero address not allowed");
        lockonVesting.deposit(address(0), vestingAmount, 0);
        // Add vesting with amount equal to zero
        lockonVesting.removeBlacklistUser(accountTwo);
        vm.expectRevert("LOCKON Vesting: Vesting amount must be greater than 0");
        lockonVesting.deposit(accountTwo, 0, 0);
    }

    function test__vesting_view_function() public {
        initilizeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        // There is no vesting yet
        assertEq(lockonVesting.currentTotalClaimable(accountOne, 0), 0);
        deposit(accountOne, vestingAmount, 0);
        skip(370 days); // Skip 370 days
        deposit(accountOne, vestingAmount, 1);
        (,,,, uint256 startTime,) = lockonVesting.userVestingWallet(accountOne, 1);
        assertEq(lockonVesting.getVestingEndTime(accountOne, 1), startTime + lockonVesting.vestingCategories(0));
    }

    function test__vesting_claim_vesting() public {
        initilizeVestingContract();
        vm.stopPrank();
        uint256 accountOneBalanceBefore = lockToken.balanceOf(accountOne);
        vm.startPrank(accountOne);
        assertEq(accountOneBalanceBefore, lockToken.balanceOf(accountOne));
        uint256 vestingAmount = 100 * 1e18;
        vm.stopPrank();
        vm.startPrank(owner);
        // First vesting, claim partial amount of token since it's not fully unlocked
        deposit(accountOne, vestingAmount, 0);
        skip(40); // Skip 40s
        vm.recordLogs();
        vm.stopPrank();
        vm.prank(accountOne);
        lockonVesting.claim(0);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        /**
         * Make sure that event claim is emitted
         *
         * @dev Get the entries at index 1 since on claim vesting function call,
         * event transfer also get emitted at index 0
         */
        assertEq(entries[1].topics[0], keccak256("VestingClaimed(address,uint256,uint256)"));
        (, uint256 claimedAmount) = abi.decode(entries[1].data, (uint256, uint256));
        uint256 accountOneBalanceAfter = lockToken.balanceOf(accountOne);
        assertEq(claimedAmount, accountOneBalanceAfter - accountOneBalanceBefore);

        // Second vesting, claim fully amount of token since it's passed end time
        vm.startPrank(owner);
        deposit(accountOne, vestingAmount, 0);
        vm.stopPrank();
        skip(365 days); // Skip 365 days
        // Claimable amount should be equal to vesting amount
        accountOneBalanceBefore = lockToken.balanceOf(accountOne);
        assertEq(vestingAmount * 2 - claimedAmount, lockonVesting.currentTotalClaimable(accountOne, 0));
        vm.prank(accountOne);
        lockonVesting.claim(0);
        accountOneBalanceAfter = lockToken.balanceOf(accountOne);
        assertEq(vestingAmount * 2 - claimedAmount, accountOneBalanceAfter - accountOneBalanceBefore);
    }

    function test__vesting_claim_vesting_with_multiple_deposits() public {
        initilizeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        // Create vesting
        uint256 firstVestingStartTimestamp = block.timestamp;
        deposit(accountOne, vestingAmount, 0);
        skip(10 days); // Skip 10 days
        // Re-caculate claimable amount to assure the logic implement in the SC is correct
        uint256 cumulativeClaimableAmount;
        uint256 claimableAmount = (vestingAmount * (block.timestamp - firstVestingStartTimestamp)) / 300 days;
        // update total cumulative claimable amount
        cumulativeClaimableAmount += claimableAmount;
        // Second deposit
        vm.startPrank(owner);
        deposit(accountOne, vestingAmount, 0);
        (, uint256 userVestingAmount, uint256 claimable, uint256 accOneClaimed, uint256 startTime,) =
            lockonVesting.userVestingWallet(accountOne, 0);
        claimableAmount = vestingAmount * 10 days / 300 days;
        // check user vesting data
        assertEq(startTime, block.timestamp);
        assertEq(userVestingAmount, vestingAmount * 2 - claimableAmount);
        assertEq(claimable, vestingAmount * 10 days / 300 days);
        assertEq(accOneClaimed, 0);
        uint256 totalVestingAmount = userVestingAmount;
        skip(20 days);
        // Third deposit
        deposit(accountOne, vestingAmount, 0);
        // update claimable and vesting amount
        claimableAmount = (userVestingAmount * (20 days)) / 300 days;
        cumulativeClaimableAmount += claimableAmount;
        totalVestingAmount = totalVestingAmount + vestingAmount - claimableAmount;
        (, userVestingAmount, claimable, accOneClaimed, startTime,) = lockonVesting.userVestingWallet(accountOne, 0);
        // check user vesting data
        assertEq(userVestingAmount, totalVestingAmount);
        assertEq(claimable, cumulativeClaimableAmount);
        assertEq(cumulativeClaimableAmount, lockonVesting.currentTotalClaimable(accountOne, 0));
        // Claimable amount should be equal to vesting amount
        skip(20 days);
        uint256 accountOneBalanceBefore = lockToken.balanceOf(accountOne);
        vm.stopPrank();
        vm.prank(accountOne);
        lockonVesting.claim(0);
        (, userVestingAmount, claimable, accOneClaimed,,) = lockonVesting.userVestingWallet(accountOne, 0);
        claimableAmount = (totalVestingAmount * (20 days)) / 300 days;
        cumulativeClaimableAmount += claimableAmount;
        uint256 accountOneBalanceAfter = lockToken.balanceOf(accountOne);
        assertEq(userVestingAmount, totalVestingAmount); // total vesting amount unchanged
        assertEq(claimable, 0); // total amount user can claim reset to 0
        assertEq(accOneClaimed, userVestingAmount * (block.timestamp - startTime) / 300 days); // vested amount according to current schedule
        assertEq(accountOneBalanceAfter - accountOneBalanceBefore, cumulativeClaimableAmount); // check total number token send to user
    }

    function test__claim_vesting_fail() public {
        initilizeVestingContract();
        lockonVesting.addBlacklistUser(accountTwo);
        vm.stopPrank();
        vm.startPrank(accountTwo);
        // Add vesting for blacklist address
        vm.expectRevert("LOCKON Vesting: User has been banned from all activities in LOCKON Vesting");
        lockonVesting.claim(0);
        vm.stopPrank();
        vm.startPrank(owner);
        lockonVesting.removeBlacklistUser(accountTwo);
        vm.stopPrank();
        vm.startPrank(accountTwo);
        vm.expectRevert("LOCKON Vesting: User has nothing to claim");
        lockonVesting.claim(0);
    }

    function test__add_address_deposit_permission() public {
        initilizeVestingContract();
        vm.recordLogs();
        lockonVesting.addAddressDepositPermission(accountOne);
        assertEq(lockonVesting.isAllowedDeposit(accountOne), true);
        address[] memory listAllowedDeposit = lockonVesting.getListAllowedDeposit();
        assertEq(listAllowedDeposit[0], accountOne);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("DepositPermissionStatusUpdated(address,bool,uint256)"));
    }

    function test__remove_address_deposit_permission() public {
        initilizeVestingContract();
        vm.recordLogs();
        lockonVesting.addAddressDepositPermission(accountOne);
        lockonVesting.removeAddressDepositPermission(accountOne);
        lockonVesting.addAddressDepositPermission(accountOne);
        assertEq(lockonVesting.isAllowedDeposit(accountOne), true);
        address[] memory listAllowedDeposit = lockonVesting.getListAllowedDeposit();
        assertEq(listAllowedDeposit[0], accountOne);
        lockonVesting.removeAddressDepositPermission(accountOne);
        listAllowedDeposit = lockonVesting.getListAllowedDeposit();
        assertEq(lockonVesting.isAllowedDeposit(accountOne), false);
        assertEq(listAllowedDeposit.length, 0);
        lockonVesting.addAddressDepositPermission(accountOne);
        lockonVesting.addAddressDepositPermission(accountTwo);
        lockonVesting.removeAddressDepositPermission(accountTwo);
        listAllowedDeposit = lockonVesting.getListAllowedDeposit();
        assertEq(listAllowedDeposit[0], accountOne);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("DepositPermissionStatusUpdated(address,bool,uint256)"));
        assertEq(entries[1].topics[0], keccak256("DepositPermissionStatusUpdated(address,bool,uint256)"));
        assertEq(entries[2].topics[0], keccak256("DepositPermissionStatusUpdated(address,bool,uint256)"));
        assertEq(entries[3].topics[0], keccak256("DepositPermissionStatusUpdated(address,bool,uint256)"));
    }

    function test__add_blacklist_address() public {
        initilizeVestingContract();
        vm.recordLogs();
        lockonVesting.addBlacklistUser(accountOne);
        assertEq(lockonVesting.isBlacklistUser(accountOne), true);
        address[] memory blacklist = lockonVesting.getBlacklist();
        assertEq(blacklist[0], accountOne);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("UserBlacklistUserAdded(address,bool,uint256)"));
    }

    function test__remove_blacklist_address() public {
        initilizeVestingContract();
        vm.recordLogs();
        lockonVesting.addBlacklistUser(accountOne);
        lockonVesting.removeBlacklistUser(accountOne);
        lockonVesting.addBlacklistUser(accountOne);
        assertEq(lockonVesting.isBlacklistUser(accountOne), true);
        address[] memory blacklist = lockonVesting.getBlacklist();
        assertEq(blacklist[0], accountOne);
        lockonVesting.removeBlacklistUser(accountOne);
        blacklist = lockonVesting.getBlacklist();
        assertEq(lockonVesting.isBlacklistUser(accountOne), false);
        assertEq(blacklist.length, 0);
        lockonVesting.addBlacklistUser(accountOne);
        lockonVesting.addBlacklistUser(accountTwo);
        lockonVesting.removeBlacklistUser(accountTwo);
        blacklist = lockonVesting.getBlacklist();
        assertEq(blacklist[0], accountOne);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("UserBlacklistUserAdded(address,bool,uint256)"));
        assertEq(entries[1].topics[0], keccak256("UserBlacklistUserRemoved(address,bool,uint256)"));
        assertEq(entries[2].topics[0], keccak256("UserBlacklistUserAdded(address,bool,uint256)"));
        assertEq(entries[1].topics[0], keccak256("UserBlacklistUserRemoved(address,bool,uint256)"));
    }

    function test__add_and_remove_address_deposit_permission_fail() public {
        initilizeVestingContract();
        lockonVesting.addAddressDepositPermission(accountOne);
        vm.expectRevert("LOCKON Vesting: Zero address not allowed");
        lockonVesting.addAddressDepositPermission(address(0));
        vm.expectRevert("LOCKON Vesting: List allowed deposit address already contains this address");
        lockonVesting.addAddressDepositPermission(accountOne);
        vm.expectRevert("LOCKON Vesting: Zero address not allowed");
        lockonVesting.removeAddressDepositPermission(address(0));
        vm.expectRevert("LOCKON Vesting: List allowed deposit address does not contain this address");
        lockonVesting.removeAddressDepositPermission(accountTwo);
    }

    function test__add_and_remove_blacklist_address_fail() public {
        initilizeVestingContract();
        lockonVesting.addBlacklistUser(accountOne);
        vm.expectRevert("LOCKON Vesting: Zero address not allowed");
        lockonVesting.addBlacklistUser(address(0));
        vm.expectRevert("LOCKON Vesting: Blacklist already contains this address");
        lockonVesting.addBlacklistUser(accountOne);
        vm.expectRevert("LOCKON Vesting: Zero address not allowed");
        lockonVesting.removeBlacklistUser(address(0));
        vm.expectRevert("LOCKON Vesting: Blacklist does not contain this address");
        lockonVesting.removeBlacklistUser(accountTwo);
    }

    function test__set_vesting_categories() public {
        initilizeVestingContract();
        uint256[] memory vestingCategoryIds = new uint256[](2);
        vestingCategoryIds[0] = 0;
        vestingCategoryIds[1] = 2;
        uint256[] memory vestingCategoryValues = new uint256[](2);
        vestingCategoryValues[0] = 100 days;
        vestingCategoryValues[1] = 200 days;
        lockonVesting.setVestingCategories(vestingCategoryIds, vestingCategoryValues);
        assertEq(lockonVesting.vestingCategories(0), 100 days);
        assertEq(lockonVesting.vestingCategories(1), 300 days); // no change in data
        assertEq(lockonVesting.vestingCategories(2), 200 days);
    }

    function test__set_vesting_categories_fail() public {
        initilizeVestingContract();
        uint256[] memory vestingCategoryIds = new uint256[](2);
        vestingCategoryIds[0] = 0;
        vestingCategoryIds[1] = 2;
        uint256[] memory vestingCategoryValues = new uint256[](3);
        vestingCategoryValues[0] = 100 days;
        vestingCategoryValues[1] = 200 days;
        vestingCategoryValues[1] = 300 days;
        vm.expectRevert("The list for category ID and category value must have equal length");
        lockonVesting.setVestingCategories(vestingCategoryIds, vestingCategoryValues);
    }

    function test_pause_and_unpause() public {
        initilizeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        lockToken.approve(address(lockonVesting), vestingAmount);
        lockonVesting.pause();
        // Cannot do any action when contract is paused
        vm.expectRevert(EnforcedPause.selector);
        lockonVesting.deposit(accountOne, vestingAmount, 0);
        vm.expectRevert(EnforcedPause.selector);
        lockonVesting.claim(0);
        // Transaction can be executed normal when unpause
        lockonVesting.unPause();
        lockonVesting.deposit(accountOne, vestingAmount, 0);
    }

    function test___receiver_func() public {
        initilizeVestingContract();
        (bool sent,) = address(lockonVesting).call{value: 1 ether}("");
        require(sent, "Failed to send Ether");
        payable(address(lockonVesting)).transfer(1 ether);
    }
}
