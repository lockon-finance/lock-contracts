// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {LockToken} from "../contracts/LockToken.sol";
import {LockonVesting} from "../contracts/LockonVesting.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract LockonVestingTest is Test {
    LockonVesting public lockonVesting;
    LockToken public lockToken;
    ERC1967Proxy tokenProxy;
    ERC1967Proxy lockonVestingProxy;
    uint256[] vestingCategoryIds;
    uint256[] vestingPeriods;
    uint256 constant VALIDATOR_PRIVATE_KEY = 123;
    address public constant OWNER = address(bytes20(bytes("OWNER")));
    address public constant ACCOUNT_ONE = address(1);
    address public constant ACCOUNT_TWO = address(2);
    address public validator = vm.addr(VALIDATOR_PRIVATE_KEY);

    error OwnableUnauthorizedAccount(address account);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error EnforcedPause();

    function setUp() public {
        vm.startPrank(OWNER);
        bytes memory tokenData = abi.encodeCall(lockToken.initialize, ("LockToken", "LOCK", OWNER, validator));
        lockToken = new LockToken();
        tokenProxy = new ERC1967Proxy(address(lockToken), tokenData);
        lockToken = LockToken(address(tokenProxy));
        lockonVesting = new LockonVesting();
        deal(OWNER, 100 ether);
        vestingCategoryIds = new uint256[](2);
        vestingCategoryIds[0] = 0;
        vestingCategoryIds[1] = 2;
        vestingPeriods = new uint256[](2);
        vestingPeriods[0] = 300 days;
        vestingPeriods[1] = 300 days;
    }

    uint256 constant MAX_PARALLEL_VESTING = 50;

    function initializeVestingContract() public {
        bytes memory lockonVestingData =
            abi.encodeCall(lockonVesting.initialize, (OWNER, address(lockToken), vestingCategoryIds, vestingPeriods));
        lockonVestingProxy = new ERC1967Proxy(address(lockonVesting), lockonVestingData);
        lockonVesting = LockonVesting(address(lockonVestingProxy));
    }

    function test_initialize_fail_owner_zero_address() public {
        vm.expectRevert("LOCKON Vesting: owner is the zero address");
        bytes memory lockonVestingData = abi.encodeCall(
            lockonVesting.initialize, (address(0), address(lockToken), vestingCategoryIds, vestingPeriods)
        );
        lockonVestingProxy = new ERC1967Proxy(address(lockonVesting), lockonVestingData);
        lockonVesting = LockonVesting(address(lockonVestingProxy));
    }

    function test_initialize_fail_lock_token_zero_address() public {
        vm.expectRevert("LOCKON Vesting: lockToken is the zero address");
        bytes memory lockonVestingData =
            abi.encodeCall(lockonVesting.initialize, (OWNER, address(0), vestingCategoryIds, vestingPeriods));
        lockonVestingProxy = new ERC1967Proxy(address(lockonVesting), lockonVestingData);
        lockonVesting = LockonVesting(address(lockonVestingProxy));
    }

    function deposit(address user, uint256 _amount, uint256 categoryId) public {
        lockToken.approve(address(lockonVesting), _amount);
        lockonVesting.deposit(user, _amount, categoryId);
    }

    function test__OWNER_add_vesting_wallet() public {
        initializeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        lockToken.approve(address(lockonVesting), vestingAmount);
        vm.recordLogs();
        lockonVesting.deposit(ACCOUNT_ONE, vestingAmount, 0); // Vesting for 60 seconds
        Vm.Log[] memory entries = vm.getRecordedLogs();
        /**
         * Make sure that event add is emitted
         *
         * @dev Get the entries at index 1 since on add vesting function call,
         * event transfer from also get emitted at index 0, enum convert to uint
         */
        assertEq(entries[1].topics[0], keccak256("VestingDeposited(address,address,uint256,uint256,uint256,uint256,uint8)"));
    }

    function test__deposit_fail() public {
        initializeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        // Only OWNER check
        vm.stopPrank();
        vm.prank(ACCOUNT_ONE);
        vm.expectRevert("LOCKON Vesting: Forbidden");
        lockonVesting.deposit(ACCOUNT_ONE, vestingAmount, 0);
        // Not enough allowance check
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20InsufficientAllowance.selector,
                address(lockonVesting),
                lockToken.allowance(OWNER, address(lockonVesting)),
                vestingAmount
            )
        );
        vm.startPrank(OWNER);
        lockonVesting.deposit(ACCOUNT_TWO, vestingAmount, 0);
        // Add blacklist address at LockToken level
        lockToken.addBlacklistUser(ACCOUNT_TWO);
        vm.expectRevert("LOCKON Vesting: User has been banned from all activities in LOCKON Vesting");
        lockonVesting.deposit(ACCOUNT_TWO, vestingAmount, 0);
        // Add vesting for zero address
        vm.expectRevert("LOCKON Vesting: Zero address not allowed");
        lockonVesting.deposit(address(0), vestingAmount, 0);
        // Add vesting with amount equal to zero
        lockToken.removeBlacklistUser(ACCOUNT_TWO);
        vm.expectRevert("LOCKON Vesting: Vesting amount must be greater than 0");
        lockonVesting.deposit(ACCOUNT_TWO, 0, 0);
        vm.expectRevert("LOCKON Vesting: Category do not exist");
        lockonVesting.deposit(ACCOUNT_TWO, vestingAmount, 5);
    }

    function test__vesting_view_function() public {
        initializeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        // There is no vesting yet
        (uint256 claimableAmount, uint256 lockedAmount) = lockonVesting.getVestingStatus(ACCOUNT_ONE, 0);
        assertEq(claimableAmount, 0);
        assertEq(lockedAmount, 0);
        deposit(ACCOUNT_ONE, vestingAmount, 0);
        skip(370 days); // Skip 370 days
        deposit(ACCOUNT_ONE, vestingAmount, 2);
        (,,, uint256 startTime) = lockonVesting.userVestingWallets(ACCOUNT_ONE, 2, 0);
        uint256 latestEndTime = lockonVesting.getVestingEndTime(ACCOUNT_ONE, 2);
        assertEq(latestEndTime, startTime + lockonVesting.vestingCategories(2));
    }

    function test__getVestingStatus_with_partial_vesting() public {
        initializeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        deposit(ACCOUNT_ONE, vestingAmount, 0);
        skip(150 days);
        (uint256 claimableAmount, uint256 lockedAmount) = lockonVesting.getVestingStatus(ACCOUNT_ONE, 0);
        assertEq(claimableAmount, vestingAmount * 150 days / 300 days);
        assertEq(lockedAmount, vestingAmount);
    }

    function test__getVestingStatus_after_claim() public {
        initializeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        deposit(ACCOUNT_ONE, vestingAmount, 0);
        skip(150 days);
        (uint256 claimableBefore, uint256 lockedBefore) = lockonVesting.getVestingStatus(ACCOUNT_ONE, 0);
        vm.stopPrank();
        vm.prank(ACCOUNT_ONE);
        lockonVesting.claim(0);
        (uint256 claimableAfter, uint256 lockedAfter) = lockonVesting.getVestingStatus(ACCOUNT_ONE, 0);
        assertEq(claimableAfter, 0);
        assertEq(lockedAfter, vestingAmount - claimableBefore);
    }

    function test__getVestingStatus_with_multiple_periods() public {
        initializeVestingContract();
        uint256 firstDeposit = 100 * 1e18;
        uint256 secondDeposit = 200 * 1e18;
        deposit(ACCOUNT_ONE, firstDeposit, 0);
        skip(100 days);
        deposit(ACCOUNT_ONE, secondDeposit, 0);
        skip(50 days);
        (uint256 claimableAmount, uint256 lockedAmount) = lockonVesting.getVestingStatus(ACCOUNT_ONE, 0);
        uint256 expectedClaimableFirst = firstDeposit * 150 days / 300 days;
        uint256 expectedClaimableSecond = secondDeposit * 50 days / 300 days;
        assertEq(claimableAmount, expectedClaimableFirst + expectedClaimableSecond);
        assertEq(lockedAmount, firstDeposit + secondDeposit);
    }

    function test__getVestingStatus_with_carried_over_amount() public {
        initializeVestingContract();
        uint256 firstDeposit = 100 * 1e18;
        deposit(ACCOUNT_ONE, firstDeposit, 0);
        skip(vestingPeriods[0] + 1 days);
        uint256 secondDeposit = 200 * 1e18;
        deposit(ACCOUNT_ONE, secondDeposit, 0);
        (uint256 claimableAmount, uint256 lockedAmount) = lockonVesting.getVestingStatus(ACCOUNT_ONE, 0);
        assertEq(claimableAmount, firstDeposit);
        assertEq(lockedAmount, firstDeposit + secondDeposit);
    }

    function test__vesting_claim_vesting() public {
        initializeVestingContract();
        vm.stopPrank();
        uint256 ACCOUNT_ONEBalanceBefore = lockToken.balanceOf(ACCOUNT_ONE);
        vm.startPrank(ACCOUNT_ONE);
        assertEq(ACCOUNT_ONEBalanceBefore, lockToken.balanceOf(ACCOUNT_ONE));
        uint256 vestingAmount = 100 * 1e18;
        vm.stopPrank();
        vm.startPrank(OWNER);
        // First vesting, claim partial amount of token since it's not fully unlocked
        deposit(ACCOUNT_ONE, vestingAmount, 0);
        assertEq(lockonVesting.getAvailableSlots(ACCOUNT_ONE, 0), 49);
        skip(40); // Skip 40s
        vm.recordLogs();
        vm.stopPrank();
        vm.prank(ACCOUNT_ONE);
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
        uint256 ACCOUNT_ONEBalanceAfter = lockToken.balanceOf(ACCOUNT_ONE);
        assertEq(claimedAmount, ACCOUNT_ONEBalanceAfter - ACCOUNT_ONEBalanceBefore);

        // Second deposit creates a new parallel vesting period
        vm.startPrank(OWNER);
        deposit(ACCOUNT_ONE, vestingAmount, 0);
        vm.stopPrank();
        skip(365 days); // Skip 365 days - both periods should be fully matured
        // With parallel vesting, both periods are now fully claimable
        ACCOUNT_ONEBalanceBefore = lockToken.balanceOf(ACCOUNT_ONE);
        (uint256 totalClaimable,) = lockonVesting.getVestingStatus(ACCOUNT_ONE, 0);
        vm.prank(ACCOUNT_ONE);
        lockonVesting.claim(0);
        ACCOUNT_ONEBalanceAfter = lockToken.balanceOf(ACCOUNT_ONE);

        // Verify all periods removed
        assertEq(lockonVesting.getAvailableSlots(ACCOUNT_ONE, 0), 50);
        // Check that we received the remaining tokens from both periods
        assertEq(totalClaimable, ACCOUNT_ONEBalanceAfter - ACCOUNT_ONEBalanceBefore);
    }

    function test__claim_single_period_removes_last_element() public {
        initializeVestingContract();
        uint256 depositAmount = 100 * 1e18;
        deposit(ACCOUNT_ONE, depositAmount, 0);
        assertEq(lockonVesting.getAvailableSlots(ACCOUNT_ONE, 0), 49);
        skip(vestingPeriods[0] + 1 days);
        uint256 balanceBefore = lockToken.balanceOf(ACCOUNT_ONE);
        (uint256 expectedClaimable,) = lockonVesting.getVestingStatus(ACCOUNT_ONE, 0);
        assertEq(expectedClaimable, depositAmount);
        vm.stopPrank();
        vm.recordLogs();
        vm.prank(ACCOUNT_ONE);
        lockonVesting.claim(0);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[1].topics[0], keccak256("VestingClaimed(address,uint256,uint256)"));
        (, uint256 claimedAmount) = abi.decode(entries[1].data, (uint256, uint256));
        assertEq(claimedAmount, depositAmount);
        uint256 balanceAfter = lockToken.balanceOf(ACCOUNT_ONE);
        assertEq(balanceAfter - balanceBefore, depositAmount);
        vm.startPrank(OWNER);
        assertEq(lockonVesting.getAvailableSlots(ACCOUNT_ONE, 0), 50);
    }

    function test__remove_last_element_in_array() public {
        initializeVestingContract();
        uint256 depositAmount = 100 * 1e18;
        deposit(ACCOUNT_ONE, depositAmount, 0);
        skip(50 days);
        deposit(ACCOUNT_ONE, depositAmount * 2, 0);
        assertEq(lockonVesting.getAvailableSlots(ACCOUNT_ONE, 0), 48);
        skip(vestingPeriods[0] - 50 days + 1 days);
        deposit(ACCOUNT_ONE, depositAmount * 3, 0);
        assertEq(lockonVesting.getAvailableSlots(ACCOUNT_ONE, 0), 48);
        skip(50 days + 1 days);
        (uint256 expectedClaimable,) = lockonVesting.getVestingStatus(ACCOUNT_ONE, 0);
        assertGt(expectedClaimable, depositAmount * 2);
        vm.stopPrank();
        vm.recordLogs();
        vm.prank(ACCOUNT_ONE);
        lockonVesting.claim(0);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[1].topics[0], keccak256("VestingClaimed(address,uint256,uint256)"));
        (, uint256 claimedAmount) = abi.decode(entries[1].data, (uint256, uint256));
        assertEq(claimedAmount, expectedClaimable);
        vm.startPrank(OWNER);
        assertEq(lockonVesting.getAvailableSlots(ACCOUNT_ONE, 0), 49);
    }

    function test__parallel_vesting_deposit_with_available_slots() public {
        initializeVestingContract();
        uint256 depositAmount = 1000 * 1e18;
        assertEq(lockonVesting.getAvailableSlots(ACCOUNT_ONE, 0), MAX_PARALLEL_VESTING);
        deposit(ACCOUNT_ONE, depositAmount, 0);
        assertEq(lockonVesting.getAvailableSlots(ACCOUNT_ONE, 0), MAX_PARALLEL_VESTING - 1);
        skip(30 days);
        deposit(ACCOUNT_ONE, depositAmount * 2, 0);
        assertEq(lockonVesting.getAvailableSlots(ACCOUNT_ONE, 0), MAX_PARALLEL_VESTING - 2);
        (uint256 totalClaimable,) = lockonVesting.getVestingStatus(ACCOUNT_ONE, 0);
        assertGt(totalClaimable, 0);
    }

    function test__parallel_vesting_deposit_no_slots_no_matured() public {
        initializeVestingContract();
        uint256 depositAmount = 100 * 1e18;
        for (uint256 i = 0; i < MAX_PARALLEL_VESTING - 1; i++) {
            deposit(ACCOUNT_ONE, depositAmount, 0);
        }
        assertEq(lockonVesting.getAvailableSlots(ACCOUNT_ONE, 0), 1);
        deposit(ACCOUNT_ONE, depositAmount, 0);
        assertEq(lockonVesting.getAvailableSlots(ACCOUNT_ONE, 0), 0);
        skip(10 days);
        uint256 newDepositAmount = 500 * 1e18;
        deposit(ACCOUNT_ONE, newDepositAmount, 0);
        assertEq(lockonVesting.getAvailableSlots(ACCOUNT_ONE, 0), 0);
        uint256 oldestIndex = 0;
        (, uint256 carriedOverClaimableAmount, ,) = lockonVesting.userVestingWallets(ACCOUNT_ONE, 0, oldestIndex);
        assertGt(carriedOverClaimableAmount, 0, "Overwritten slot should have accumulated claimable amount");
    }

    function test__parallel_vesting_deposit_no_slots_with_matured() public {
        initializeVestingContract();
        uint256 depositAmount = 100 * 1e18;
        for (uint256 i = 0; i < 5; i++) {
            deposit(ACCOUNT_ONE, depositAmount, 0);
            skip(1 days);
        }
        assertEq(lockonVesting.getAvailableSlots(ACCOUNT_ONE, 0), 45);
        skip(vestingPeriods[0] + 1 days);
        assertEq(lockonVesting.getAvailableSlots(ACCOUNT_ONE, 0), 50);

        for (uint256 i = 0; i < 45; i++) {
            deposit(ACCOUNT_ONE, depositAmount, 0);
        }
        uint256 availableSlots = lockonVesting.getAvailableSlots(ACCOUNT_ONE, 0);
        assertEq(availableSlots, 5);
    }

    function test__deposit_with_all_50_matured() public {
        initializeVestingContract();
        uint256 depositAmount = 100 * 1e18;
        for (uint256 i = 0; i < MAX_PARALLEL_VESTING; i++) {
            deposit(ACCOUNT_ONE, depositAmount, 0);
        }
        assertEq(lockonVesting.getAvailableSlots(ACCOUNT_ONE, 0), 0);
        skip(vestingPeriods[0] + 1 days);
        assertEq(lockonVesting.getAvailableSlots(ACCOUNT_ONE, 0), 50);
        vm.stopPrank();
        vm.prank(ACCOUNT_ONE);
        lockonVesting.claim(0);
        vm.startPrank(OWNER);
        assertEq(lockonVesting.getAvailableSlots(ACCOUNT_ONE, 0), 50);
        uint256 newDepositAmount = 500 * 1e18;
        deposit(ACCOUNT_ONE, newDepositAmount, 0);
        assertEq(lockonVesting.getAvailableSlots(ACCOUNT_ONE, 0), 49);
    }

    function test__parallel_vesting_matured_slot_reuse_priority() public {
        initializeVestingContract();
        uint256 depositAmount = 100 * 1e18;
        deposit(ACCOUNT_ONE, depositAmount, 0);
        skip(10 days);
        deposit(ACCOUNT_ONE, depositAmount, 0);
        skip(10 days);
        deposit(ACCOUNT_ONE, depositAmount, 0);

        skip(vestingPeriods[0] / 2);
        (uint256 claimableBeforeMaturity,) = lockonVesting.getVestingStatus(ACCOUNT_ONE, 0);
        assertGt(claimableBeforeMaturity, 0, "Should have claimable amount after partial vesting");

        vm.stopPrank();
        vm.startPrank(ACCOUNT_ONE);
        lockonVesting.claim(0);
        vm.stopPrank();
        vm.startPrank(OWNER);

        skip(vestingPeriods[0] / 2 + 1 days);
        (uint256 vestingAmount0Before, uint256 carriedOverClaimableAmount0Before, uint256 claimedAmount0Before, uint256 startTime0) =
            lockonVesting.userVestingWallets(ACCOUNT_ONE, 0, 0);

        uint256 elapsed = block.timestamp - startTime0;
        uint256 claimable0;
        if (elapsed >= vestingPeriods[0]) {
            claimable0 = vestingAmount0Before;
        } else {
            claimable0 = (vestingAmount0Before * elapsed) / vestingPeriods[0];
        }
        uint256 expectedAccumulated = claimable0 + carriedOverClaimableAmount0Before - claimedAmount0Before;
        uint256 newDepositAmount = 500 * 1e18;
        deposit(ACCOUNT_ONE, newDepositAmount, 0);

        (uint256 vestingAmount, uint256 carriedOverClaimableAmount, uint256 claimedAmount,) =
            lockonVesting.userVestingWallets(ACCOUNT_ONE, 0, 0);
        assertGt(carriedOverClaimableAmount, 0, "Reused slot should have accumulated the unclaimed amount");
        assertEq(carriedOverClaimableAmount, expectedAccumulated,
            "carriedOverClaimableAmount should equal unclaimed amount from the reused slot 0 only");
        assertEq(vestingAmount, newDepositAmount,
            "vestingAmount should be only the new deposit amount");
        assertEq(claimedAmount, 0, "claimedAmount should be reset to 0");

        assertEq(lockonVesting.getAvailableSlots(ACCOUNT_ONE, 0), 49); // 50 - 3 + 2 remaining matured
    }

    function test__get_oldest_vesting_info_reverts_when_no_periods() public {
        initializeVestingContract();
        vm.expectRevert("LOCKON Vesting: No vesting periods found");
        lockonVesting.getOldestActiveVestingInfo(ACCOUNT_ONE, 0);
    }

    function test__get_oldest_vesting_info_reverts_when_only_matured_periods() public {
        initializeVestingContract();
        uint256 depositAmount = 100 * 1e18;
        deposit(ACCOUNT_ONE, depositAmount, 0);
        skip(1 days);
        deposit(ACCOUNT_ONE, depositAmount, 0);
        skip(1 days);
        deposit(ACCOUNT_ONE, depositAmount, 0);
        skip(vestingPeriods[0] + 1 days);
        vm.expectRevert("LOCKON Vesting: No active vesting periods found");
        lockonVesting.getOldestActiveVestingInfo(ACCOUNT_ONE, 0);
    }

    function test__get_oldest_vesting_info_returns_oldest_active() public {
        initializeVestingContract();
        uint256 depositAmount = 100 * 1e18;
        uint256 firstDepositTime = block.timestamp;
        deposit(ACCOUNT_ONE, depositAmount, 0);
        skip(10 days);
        uint256 secondDepositTime = block.timestamp;
        deposit(ACCOUNT_ONE, depositAmount, 0);
        skip(10 days);
        uint256 thirdDepositTime = block.timestamp;
        deposit(ACCOUNT_ONE, depositAmount, 0);
        skip(50 days);
        (uint256 vestingAmount, uint256 endTime) = lockonVesting.getOldestActiveVestingInfo(ACCOUNT_ONE, 0);
        uint256 expectedEndTime = firstDepositTime + vestingPeriods[0];
        assertEq(endTime, expectedEndTime, "End time should match first deposit");
        assertLt(vestingAmount, depositAmount, "Vesting amount should be less than deposit due to partial claim");
        assertGt(vestingAmount, 0, "Vesting amount should be greater than 0");
    }

    function test__claim_vesting_fail() public {
        initializeVestingContract();
        // Blacklist ACCOUNT_TWO at token level
        lockToken.addBlacklistUser(ACCOUNT_TWO);
        vm.stopPrank();
        vm.startPrank(ACCOUNT_TWO);
        // Add vesting for blacklist address
        vm.expectRevert("LOCKON Vesting: User has been banned from all activities in LOCKON Vesting");
        lockonVesting.claim(0);
        vm.stopPrank();
        vm.startPrank(OWNER);
        lockToken.removeBlacklistUser(ACCOUNT_TWO);
        // Test with ACCOUNT_ONE who has no vesting
        vm.stopPrank();
        vm.startPrank(ACCOUNT_ONE);
        vm.expectRevert("LOCKON Vesting: User has nothing to claim");
        lockonVesting.claim(0);
    }

    function test__add_address_deposit_permission() public {
        initializeVestingContract();
        vm.recordLogs();
        lockonVesting.addAddressDepositPermission(ACCOUNT_ONE);
        assertEq(lockonVesting.isAllowedDeposit(ACCOUNT_ONE), true);
        address[] memory listAllowedDeposit = lockonVesting.getListAllowedDeposit();
        assertEq(listAllowedDeposit[0], ACCOUNT_ONE);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("DepositPermissionStatusUpdated(address,address,bool,uint256)"));
    }

    function test__remove_address_deposit_permission() public {
        initializeVestingContract();
        vm.recordLogs();
        lockonVesting.addAddressDepositPermission(ACCOUNT_ONE);
        lockonVesting.removeAddressDepositPermission(ACCOUNT_ONE);
        lockonVesting.addAddressDepositPermission(ACCOUNT_ONE);
        assertEq(lockonVesting.isAllowedDeposit(ACCOUNT_ONE), true);
        address[] memory listAllowedDeposit = lockonVesting.getListAllowedDeposit();
        assertEq(listAllowedDeposit[0], ACCOUNT_ONE);
        lockonVesting.removeAddressDepositPermission(ACCOUNT_ONE);
        listAllowedDeposit = lockonVesting.getListAllowedDeposit();
        assertEq(lockonVesting.isAllowedDeposit(ACCOUNT_ONE), false);
        assertEq(listAllowedDeposit.length, 0);
        lockonVesting.addAddressDepositPermission(ACCOUNT_ONE);
        lockonVesting.addAddressDepositPermission(ACCOUNT_TWO);
        lockonVesting.removeAddressDepositPermission(ACCOUNT_TWO);
        listAllowedDeposit = lockonVesting.getListAllowedDeposit();
        assertEq(listAllowedDeposit[0], ACCOUNT_ONE);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("DepositPermissionStatusUpdated(address,address,bool,uint256)"));
        assertEq(entries[1].topics[0], keccak256("DepositPermissionStatusUpdated(address,address,bool,uint256)"));
        assertEq(entries[2].topics[0], keccak256("DepositPermissionStatusUpdated(address,address,bool,uint256)"));
        assertEq(entries[3].topics[0], keccak256("DepositPermissionStatusUpdated(address,address,bool,uint256)"));
    }

    function test__add_and_remove_address_deposit_permission_fail() public {
        initializeVestingContract();
        lockonVesting.addAddressDepositPermission(ACCOUNT_ONE);
        vm.expectRevert("LOCKON Vesting: Zero address not allowed");
        lockonVesting.addAddressDepositPermission(address(0));
        vm.expectRevert("LOCKON Vesting: List allowed deposit address already contains this address");
        lockonVesting.addAddressDepositPermission(ACCOUNT_ONE);
        vm.expectRevert("LOCKON Vesting: Zero address not allowed");
        lockonVesting.removeAddressDepositPermission(address(0));
        vm.expectRevert("LOCKON Vesting: List allowed deposit address does not contain this address");
        lockonVesting.removeAddressDepositPermission(ACCOUNT_TWO);
    }

    function test__set_vesting_categories() public {
        initializeVestingContract();
        uint256[] memory updatedVestingCategoryIds = new uint256[](2);
        updatedVestingCategoryIds[0] = 0;
        updatedVestingCategoryIds[1] = 2;
        uint256[] memory updatedVestingCategoryValues = new uint256[](2);
        updatedVestingCategoryValues[0] = 100 days;
        updatedVestingCategoryValues[1] = 200 days;
        lockonVesting.setVestingCategories(updatedVestingCategoryIds, updatedVestingCategoryValues);
        assertEq(lockonVesting.vestingCategories(0), 100 days);
        assertEq(lockonVesting.vestingCategories(1), 0); // no change in data
        assertEq(lockonVesting.vestingCategories(2), 200 days);
    }

    function test__set_vesting_categories_fail() public {
        initializeVestingContract();
        uint256[] memory updatedVestingCategoryIds = new uint256[](2);
        updatedVestingCategoryIds[0] = 0;
        updatedVestingCategoryIds[1] = 2;
        uint256[] memory updatedVestingCategoryValues = new uint256[](3);
        updatedVestingCategoryValues[0] = 100 days;
        updatedVestingCategoryValues[1] = 200 days;
        updatedVestingCategoryValues[2] = 300 days;
        vm.expectRevert("LOCKON Vesting: The list for category ID and category value must have equal length");
        lockonVesting.setVestingCategories(updatedVestingCategoryIds, updatedVestingCategoryValues);
    }

    function test_pause_and_unpause() public {
        initializeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        lockToken.approve(address(lockonVesting), vestingAmount);
        lockonVesting.pause();
        // Cannot do any action when contract is paused
        vm.expectRevert(EnforcedPause.selector);
        lockonVesting.deposit(ACCOUNT_ONE, vestingAmount, 0);
        vm.expectRevert(EnforcedPause.selector);
        lockonVesting.claim(0);
        // Transaction can be executed normal when unpause
        lockonVesting.unPause();
        lockonVesting.deposit(ACCOUNT_ONE, vestingAmount, 0);
    }

    function test_initialize_fail_different_length() public {
        uint256[] memory failVestingCategoryIds = new uint256[](2);
        failVestingCategoryIds[0] = 0;
        failVestingCategoryIds[1] = 1;
        uint256[] memory failVestingPeriods = new uint256[](3);
        failVestingPeriods[0] = 100 days;
        failVestingPeriods[1] = 200 days;
        failVestingPeriods[2] = 300 days;

        vm.expectRevert("LOCKON Vesting: categoryIds and vestingPeriods length mismatch");
        bytes memory lockonVestingData = abi.encodeCall(
            lockonVesting.initialize, (OWNER, address(lockToken), failVestingCategoryIds, failVestingPeriods)
        );
        lockonVestingProxy = new ERC1967Proxy(address(lockonVesting), lockonVestingData);
    }

    function test_initialize_fail_zero_vesting_period() public {
        uint256[] memory failVestingCategoryIds = new uint256[](2);
        failVestingCategoryIds[0] = 0;
        failVestingCategoryIds[1] = 1;
        uint256[] memory failVestingPeriods = new uint256[](2);
        failVestingPeriods[0] = 100 days;
        failVestingPeriods[1] = 0; // Invalid vesting period

        vm.expectRevert("LOCKON Vesting: Vesting period must be greater than 0");
        bytes memory lockonVestingData = abi.encodeCall(
            lockonVesting.initialize, (OWNER, address(lockToken), failVestingCategoryIds, failVestingPeriods)
        );
        lockonVestingProxy = new ERC1967Proxy(address(lockonVesting), lockonVestingData);
    }

    function test_initialize_empty_category_id() public {
        uint256[] memory failVestingCategoryIds = new uint256[](0);
        uint256[] memory failVestingPeriods = new uint256[](0);

        bytes memory lockonVestingData = abi.encodeCall(
            lockonVesting.initialize, (OWNER, address(lockToken), failVestingCategoryIds, failVestingPeriods)
        );
        lockonVestingProxy = new ERC1967Proxy(address(lockonVesting), lockonVestingData);

        assertEq(lockonVesting.vestingCategories(0), 0);
        assertEq(lockonVesting.vestingCategories(1), 0);
        assertEq(lockonVesting.vestingCategories(2), 0);
    }

    function test_vesting_period_set_to_zero_after_deposit() public {
        // Initialize with normal vesting period
        uint256[] memory vestingCategoryIds = new uint256[](1);
        vestingCategoryIds[0] = 6;
        uint256[] memory vestingPeriods = new uint256[](1);
        vestingPeriods[0] = 300 days;

        bytes memory lockonVestingData =
            abi.encodeCall(lockonVesting.initialize, (OWNER, address(lockToken), vestingCategoryIds, vestingPeriods));
        lockonVestingProxy = new ERC1967Proxy(address(lockonVesting), lockonVestingData);
        lockonVesting = LockonVesting(address(lockonVestingProxy));

        uint256 vestingAmount = 100 * 1e18;

        // Make a deposit with normal vesting period
        lockToken.approve(address(lockonVesting), vestingAmount);
        lockonVesting.deposit(ACCOUNT_ONE, vestingAmount, 6);

        // Verify partial vesting after some time
        skip(30 days);
        (uint256 partialClaimable,) = lockonVesting.getVestingStatus(ACCOUNT_ONE, 6);
        assertEq(partialClaimable, vestingAmount * 30 days / 300 days, "Should have partial vesting after 30 days");

        // Now set the vesting period to 0 (immediate vesting)
        uint256[] memory updateIds = new uint256[](1);
        updateIds[0] = 6;
        uint256[] memory updatePeriods = new uint256[](1);
        updatePeriods[0] = 0;
        lockonVesting.setVestingCategories(updateIds, updatePeriods);

        // After setting to 0, full amount should be immediately claimable
        (uint256 fullClaimable,) = lockonVesting.getVestingStatus(ACCOUNT_ONE, 6);
        assertEq(fullClaimable, vestingAmount, "Full amount should be claimable when vestingPeriods is 0");

        // Claim all tokens
        vm.stopPrank();
        vm.prank(ACCOUNT_ONE);
        lockonVesting.claim(6);
        assertEq(lockToken.balanceOf(ACCOUNT_ONE), vestingAmount, "All tokens should be claimed");

        // Try to deposit again - should fail because category is now 0 (non-existent)
        vm.startPrank(OWNER);
        lockToken.approve(address(lockonVesting), vestingAmount);
        vm.expectRevert("LOCKON Vesting: Category do not exist");
        lockonVesting.deposit(ACCOUNT_ONE, vestingAmount, 6);
    }
}
