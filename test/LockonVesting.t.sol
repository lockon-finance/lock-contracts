// SPDX-License-Identifier: UNLICENSED
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

    function addVestingWallet(address _vestedAddress, uint256 _amount, ILockonVesting.VestingTag _vestingTag) public {
        lockToken.approve(address(lockonVesting), _amount);
        lockonVesting.addVestingWallet(_vestedAddress, _amount, _vestingTag);
    }

    function test__owner_add_vesting_wallet() public {
        initilizeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        lockToken.approve(address(lockonVesting), vestingAmount);
        vm.recordLogs();
        lockonVesting.addVestingWallet(accountOne, vestingAmount, ILockonVesting.VestingTag.LOCK_STAKING_ADD); // Vesting for 60 seconds
        Vm.Log[] memory entries = vm.getRecordedLogs();
        /**
         * Make sure that event add is emitted
         *
         * @dev Get the entries at index 1 since on add vesting function call,
         * event transfer from also get emitted at index 0, enum convert to uint
         */
        assertEq(entries[1].topics[0], keccak256("VestingWalletAdded(address,address,uint256,uint256,uint256,uint8)"));
    }

    function test__add_vesting_wallet_fail() public {
        initilizeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        // Only owner check
        vm.stopPrank();
        vm.prank(accountOne);
        vm.expectRevert("Lockon Vesting: Forbidden");
        lockonVesting.addVestingWallet(accountOne, vestingAmount, ILockonVesting.VestingTag.LOCK_STAKING_ADD);
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
        lockonVesting.addVestingWallet(accountTwo, vestingAmount, ILockonVesting.VestingTag.LOCK_STAKING_ADD);
        // Add vesting for zero address
        vm.expectRevert("Lockon Vesting: Zero address not allowed");
        lockonVesting.addVestingWallet(address(0), vestingAmount, ILockonVesting.VestingTag.LOCK_STAKING_ADD);
        // Add vesting with amount equal to zero
        vm.expectRevert("Lockon Vesting: Vesting amount must be greater than 0");
        lockonVesting.addVestingWallet(accountTwo, 0, ILockonVesting.VestingTag.LOCK_STAKING_ADD);
    }

    function test__vesting_view_function() public {
        initilizeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        addVestingWallet(accountOne, vestingAmount, ILockonVesting.VestingTag.LOCK_STAKING_ADD);
        // Releaseable = 0 at the time start vesting
        assertEq(lockonVesting.releasable(1), 0);
        uint256[] memory vestingIds = new uint256[](1);
        vestingIds[0] = 1;
        assertEq(lockonVesting.releasables(vestingIds), 0);
        skip(370 days); // Skip 370 days
        addVestingWallet(accountOne, vestingAmount, ILockonVesting.VestingTag.LOCK_STAKING_EXTEND);
        (uint256[] memory accountOneVestingIds, ILockonVesting.VestingTag[] memory accountOneVestingTags) =
            lockonVesting.getActiveVestingIdsForAddress(accountOne);
        assertEq(accountOneVestingIds.length, 2);
        assertEq(accountOneVestingIds[0], 1);
        assertEq(accountOneVestingIds[1], 2);
        assertEq(uint8(accountOneVestingTags[0]), 0);
        assertEq(uint8(accountOneVestingTags[1]), 1);
        (,,, uint256 vestingID1StartTime,) = lockonVesting.vestingWallet(1);
        assertEq(lockonVesting.getVestingEndTime(1), vestingID1StartTime + lockonVesting.vestingDuration());

        assertEq(lockonVesting.releasable(1), vestingAmount); // 100s has passed, the first vesting has been fully unlocked
    }

    function test__vesting_view_function_fail() public {
        initilizeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        addVestingWallet(accountOne, vestingAmount, ILockonVesting.VestingTag.LOCK_STAKING_ADD);
        vm.expectRevert("Lockon Vesting: Invalid vesting id");
        lockonVesting.getVestingEndTime(2);
        vm.expectRevert("Lockon Vesting: Invalid vesting id");
        lockonVesting.releasable(2);
    }

    function test__vesting_claim_vesting() public {
        initilizeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        /**
         * First vesting, claim partial amount of token since it's not fully unlocked
         *
         */
        uint256 firstVestingStartTimestamp = block.timestamp;
        addVestingWallet(accountOne, vestingAmount, ILockonVesting.VestingTag.LOCK_STAKING_ADD);
        skip(40); // Skip 40s
        // Re-calculate claimable amount to assure the logic implement in the SC is correct
        uint256 claimableAmount = (vestingAmount * (block.timestamp - firstVestingStartTimestamp)) / 300 days;
        uint256 accountOneBalanceBefore = lockToken.balanceOf(accountOne);
        assertEq(claimableAmount, lockonVesting.releasable(1));
        vm.recordLogs();
        vm.stopPrank();
        vm.prank(accountOne);
        uint256[] memory vestingArray = new uint256[](1);
        vestingArray[0] = 1;
        lockonVesting.userClaimVesting(vestingArray);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        /**
         * Make sure that event claim is emitted
         *
         * @dev Get the entries at index 1 since on claim vesting function call,
         * event transfer also get emitted at index 0
         */
        assertEq(entries[1].topics[0], keccak256("UserClaimedVesting(address,uint256[],uint256)"));
        (, uint256 eventRealeasedAmount) = abi.decode(entries[1].data, (uint256, uint256));
        uint256 accountOneBalanceAfter = lockToken.balanceOf(accountOne);
        assertEq(eventRealeasedAmount, accountOneBalanceAfter - accountOneBalanceBefore);

        /**
         * Second vesting, claim fully amount of token since it's passed end time
         *
         */
        vm.startPrank(owner);
        addVestingWallet(accountOne, vestingAmount, ILockonVesting.VestingTag.LOCK_STAKING_ADD);
        vm.stopPrank();
        skip(365 days); // Skip 365 days
        // Claimable amount should be equal to vesting amount
        assertEq(vestingAmount, lockonVesting.releasable(2));
        accountOneBalanceBefore = lockToken.balanceOf(accountOne);
        vm.prank(accountOne);
        vestingArray[0] = 2;
        lockonVesting.userClaimVesting(vestingArray);
        accountOneBalanceAfter = lockToken.balanceOf(accountOne);
        assertEq(vestingAmount, accountOneBalanceAfter - accountOneBalanceBefore);
    }

    function test__vesting_claim_array_of_vesting() public {
        initilizeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        // Create vestings
        for (uint256 i; i < 301; i++) {
            addVestingWallet(accountOne, vestingAmount, ILockonVesting.VestingTag.LOCK_STAKING_ADD);
        }
        skip(90); // Skip 90s to make sure both vesting are fully vested
        vm.recordLogs();
        vm.stopPrank();
        vm.prank(accountOne);
        uint256[] memory vestingArray = new uint256[](301);
        for (uint256 i; i < 301; i++) {
            vestingArray[i] = i + 1;
        }
        uint256 gas = gasleft();
        lockonVesting.userClaimVesting(vestingArray);
        gas -= gasleft();
        emit log_named_uint("gasUsed", gas);
    }

    function test__vesting_claim_vesting_fail() public {
        initilizeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        // Trying to claim when not unlocked
        addVestingWallet(accountOne, vestingAmount, ILockonVesting.VestingTag.LOCK_STAKING_ADD);
        vm.stopPrank();
        vm.startPrank(accountTwo);
        skip(301 days);
        uint256[] memory vestingArray = new uint256[](1);
        vestingArray[0] = 1;
        // Trying to claim other person vesting
        vm.expectRevert("Lockon Vesting: Unauthorized to claim");
        lockonVesting.userClaimVesting(vestingArray);
        // Trying to claim invalid vesting id
        vm.expectRevert("Lockon Vesting: Invalid vesting id");
        vestingArray[0] = 2;
        lockonVesting.userClaimVesting(vestingArray);
    }

    function test_set_index_staking_contract_address() public {
        initilizeVestingContract();
        lockonVesting.setIndexStakingContract(accountOne);
        assertEq(lockonVesting.indexStakingContract(), accountOne);
    }

    function test_set_index_staking_contract_address_fail() public {
        initilizeVestingContract();
        vm.stopPrank();
        vm.prank(accountOne);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, accountOne));
        lockonVesting.setIndexStakingContract(accountOne);
        vm.expectRevert("Lockon Vesting: Zero address not allowed");
        vm.prank(owner);
        lockonVesting.setIndexStakingContract(address(0));
    }

    function test_set_vesting_duration() public {
        initilizeVestingContract();
        lockonVesting.setVestingDuration(350 days);
        assertEq(lockonVesting.vestingDuration(), 350 days);
    }

    function test_set_lock_staking_contract_address() public {
        initilizeVestingContract();
        lockonVesting.setLockStakingContract(accountOne);
        assertEq(lockonVesting.lockStakingContract(), accountOne);
    }

    function test_set_lock_staking_contract_address_fail() public {
        initilizeVestingContract();
        vm.stopPrank();
        vm.prank(accountOne);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, accountOne));
        lockonVesting.setLockStakingContract(accountOne);
        vm.expectRevert("Lockon Vesting: Zero address not allowed");
        vm.prank(owner);
        lockonVesting.setLockStakingContract(address(0));
    }

    function test___receiver_func() public {
        initilizeVestingContract();
        (bool sent,) = address(lockonVesting).call{value: 1 ether}("");
        require(sent, "Failed to send Ether");
        payable(address(lockonVesting)).transfer(1 ether);
    }
}
