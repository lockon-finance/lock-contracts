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
        assertEq(entries[1].topics[0], keccak256("VestingDeposited(address,address,uint256,uint256,uint256,uint256)"));
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
        assertEq(lockonVesting.currentTotalClaimable(ACCOUNT_ONE, 0), 0);
        deposit(ACCOUNT_ONE, vestingAmount, 0);
        skip(370 days); // Skip 370 days
        deposit(ACCOUNT_ONE, vestingAmount, 2);
        (,,,, uint256 startTime,) = lockonVesting.userVestingWallet(ACCOUNT_ONE, 2);
        assertEq(lockonVesting.getVestingEndTime(ACCOUNT_ONE, 2), startTime + lockonVesting.vestingCategories(2));
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

        // Second vesting, claim fully amount of token since it's passed end time
        vm.startPrank(OWNER);
        deposit(ACCOUNT_ONE, vestingAmount, 0);
        vm.stopPrank();
        skip(365 days); // Skip 365 days
        // Claimable amount should be equal to vesting amount
        ACCOUNT_ONEBalanceBefore = lockToken.balanceOf(ACCOUNT_ONE);
        assertEq(vestingAmount * 2 - claimedAmount, lockonVesting.currentTotalClaimable(ACCOUNT_ONE, 0));
        vm.prank(ACCOUNT_ONE);
        lockonVesting.claim(0);
        ACCOUNT_ONEBalanceAfter = lockToken.balanceOf(ACCOUNT_ONE);
        assertEq(vestingAmount * 2 - claimedAmount, ACCOUNT_ONEBalanceAfter - ACCOUNT_ONEBalanceBefore);
    }

    function test__vesting_claim_vesting_with_multiple_deposits() public {
        initializeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        // Create vesting
        uint256 firstVestingStartTimestamp = block.timestamp;
        deposit(ACCOUNT_ONE, vestingAmount, 0);
        skip(10 days); // Skip 10 days
        // Re-caculate claimable amount to assure the logic implement in the SC is correct
        uint256 cumulativeClaimableAmount;
        uint256 claimableAmount = (vestingAmount * (block.timestamp - firstVestingStartTimestamp)) / 300 days;
        // update total cumulative claimable amount
        cumulativeClaimableAmount += claimableAmount;
        // Second deposit
        vm.startPrank(OWNER);
        deposit(ACCOUNT_ONE, vestingAmount, 0);
        (, uint256 userVestingAmount, uint256 claimable, uint256 accOneClaimed, uint256 startTime,) =
            lockonVesting.userVestingWallet(ACCOUNT_ONE, 0);
        claimableAmount = vestingAmount * 10 days / 300 days;
        // check user vesting data
        assertEq(startTime, block.timestamp);
        assertEq(userVestingAmount, vestingAmount * 2 - claimableAmount);
        assertEq(claimable, vestingAmount * 10 days / 300 days);
        assertEq(accOneClaimed, 0);
        uint256 totalVestingAmount = userVestingAmount;
        skip(20 days);
        // Third deposit
        deposit(ACCOUNT_ONE, vestingAmount, 0);
        // update claimable and vesting amount
        claimableAmount = (userVestingAmount * (20 days)) / 300 days;
        cumulativeClaimableAmount += claimableAmount;
        totalVestingAmount = totalVestingAmount + vestingAmount - claimableAmount;
        (, userVestingAmount, claimable, accOneClaimed, startTime,) = lockonVesting.userVestingWallet(ACCOUNT_ONE, 0);
        // check user vesting data
        assertEq(userVestingAmount, totalVestingAmount);
        assertEq(claimable, cumulativeClaimableAmount);
        assertEq(cumulativeClaimableAmount, lockonVesting.currentTotalClaimable(ACCOUNT_ONE, 0));
        // Claimable amount should be equal to vesting amount
        skip(20 days);
        uint256 ACCOUNT_ONEBalanceBefore = lockToken.balanceOf(ACCOUNT_ONE);
        vm.stopPrank();
        vm.prank(ACCOUNT_ONE);
        lockonVesting.claim(0);
        (, userVestingAmount, claimable, accOneClaimed,,) = lockonVesting.userVestingWallet(ACCOUNT_ONE, 0);
        claimableAmount = (totalVestingAmount * (20 days)) / 300 days;
        cumulativeClaimableAmount += claimableAmount;
        uint256 ACCOUNT_ONEBalanceAfter = lockToken.balanceOf(ACCOUNT_ONE);
        assertEq(userVestingAmount, totalVestingAmount); // total vesting amount unchanged
        assertEq(claimable, 0); // total amount user can claim reset to 0
        assertEq(accOneClaimed, userVestingAmount * (block.timestamp - startTime) / 300 days); // vested amount according to current schedule
        assertEq(ACCOUNT_ONEBalanceAfter - ACCOUNT_ONEBalanceBefore, cumulativeClaimableAmount); // check total number token send to user
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
        uint256 partialClaimable = lockonVesting.currentTotalClaimable(ACCOUNT_ONE, 6);
        assertEq(partialClaimable, vestingAmount * 30 days / 300 days, "Should have partial vesting after 30 days");

        // Now set the vesting period to 0 (immediate vesting)
        uint256[] memory updateIds = new uint256[](1);
        updateIds[0] = 6;
        uint256[] memory updatePeriods = new uint256[](1);
        updatePeriods[0] = 0;
        lockonVesting.setVestingCategories(updateIds, updatePeriods);

        // After setting to 0, full amount should be immediately claimable
        uint256 fullClaimable = lockonVesting.currentTotalClaimable(ACCOUNT_ONE, 6);
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
