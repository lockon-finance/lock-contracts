// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {LockStaking} from "../contracts/LockStaking.sol";
import {LockonVesting} from "../contracts/LockonVesting.sol";
import {LockToken} from "../contracts/LockToken.sol";

contract LockStakingTest is Test {
    LockStaking public lockStaking;
    LockToken public lockToken;
    LockonVesting public lockonVesting;
    uint256 constant validatorPrivateKey = 123;
    address public constant owner = address(bytes20(bytes("owner")));
    address public constant accountOne = address(1);
    address public constant accountTwo = address(2);
    address public validator = vm.addr(validatorPrivateKey);
    uint256 public constant testAccountInitialLockBalance = 1000 ether;

    error OwnableUnauthorizedAccount(address account);

    error EnforcedPause();

    function setUp() public {
        vm.startPrank(owner);
        lockToken = new LockToken();
        lockToken.initialize("LockToken", "LOCK", owner, validator);
        lockToken.transfer(accountOne, testAccountInitialLockBalance);
        lockToken.transfer(accountTwo, testAccountInitialLockBalance);
        lockStaking = new LockStaking();
        lockonVesting = new LockonVesting();
        deal(owner, 100 ether);
    }

    function initilizeAndConfig() public {
        lockonVesting.initialize(accountOne, address(lockToken));
        lockStaking.initialize(
            owner,
            address(lockonVesting),
            validator, // For testing, use validator as penalty fee receiver also
            address(lockToken),
            0,
            100000 ether,
            34730,
            2900
        );
        // Transfer lock token to contract for reward distribution
        lockToken.transfer(address(lockStaking), 100000 ether);
        vm.stopPrank();
        // Approve to pay reward
        vm.prank(validator);
        lockToken.approve(address(validator), 100000 ether);
        vm.prank(accountOne);
        lockonVesting.setLockStakingContract(address(lockStaking));
    }

    function test_add_lock_token() public {
        initilizeAndConfig();
        // Using account one
        vm.startPrank(accountOne);
        uint256 lockAmount = 1 ether;
        lockToken.approve(address(lockStaking), 1 ether);
        // Lock one Lock Token for 200 days
        vm.recordLogs();
        lockStaking.addLockToken(lockAmount, 200 days);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 accountOneBalanceAfterFirstLock = testAccountInitialLockBalance - lockAmount;
        assertEq(lockToken.balanceOf(accountOne), accountOneBalanceAfterFirstLock);
        // Get account one first lock data
        (
            uint256 lockedAmount,
            uint256 lockScore,
            uint256 lockDuration,
            uint256 lastBasicRate,
            uint256 rewardDebt,
            uint256 lockEndTimestamp
        ) = lockStaking.userInfo(accountOne);
        uint256 userLastBasicRate = 1e12;
        uint256 userLockScore =
            ((lockAmount * userLastBasicRate) * lockStaking.durationRate(200 days)) / 1e12 / lockStaking.PRECISION();
        assertEq(lockedAmount, lockAmount);
        assertEq(lockDuration, 200 days);
        assertEq(lockScore, userLockScore);
        assertEq(lastBasicRate, userLastBasicRate);
        assertEq(lockEndTimestamp, 200 days + 1);
        assertEq(rewardDebt, (userLockScore * lockStaking.rewardPerScore()) / 1e12);
        assertEq(lockStaking.totalLockScore(), lockScore);
        assertEq(lockStaking.totalLockedAmount(), lockAmount);
        // Check for emitted event
        assertEq(entries[2].topics[0], keccak256("LockTokenAdded(address,uint256,uint256,uint256,uint256,uint256)"));
        // Skip 100 days then lock another one Lock Token
        skip(100 days);
        lockToken.approve(address(lockStaking), 1 ether);
        lockStaking.addLockToken(lockAmount, 300 days);
        // Get account one second lock data
        (lockedAmount, lockScore, lockDuration, lastBasicRate, rewardDebt, lockEndTimestamp) =
            lockStaking.userInfo(accountOne);
        assertEq(lockToken.balanceOf(accountOne), accountOneBalanceAfterFirstLock - lockAmount);
        userLastBasicRate = 1e12 + (100 days * lockStaking.basicRateDivider() * 1e12) / lockStaking.PRECISION();
        uint256 newUserLockScore =
            ((lockedAmount * userLastBasicRate) * lockStaking.durationRate(300 days)) / 1e12 / lockStaking.PRECISION();

        assertEq(lockedAmount, lockAmount * 2);
        assertEq(lockScore, newUserLockScore);
        assertEq(lockDuration, 300 days);
        assertEq(lastBasicRate, userLastBasicRate);
        assertEq(lockEndTimestamp, (300 days + 200 days - 100 days) + 1);
        assertEq(lockStaking.totalLockScore(), newUserLockScore);
        assertEq(lockStaking.totalLockedAmount(), lockAmount * 2);
    }

    function test_add_lock_token_fail() public {
        lockonVesting.initialize(accountOne, address(lockToken));
        lockStaking.initialize(
            owner,
            address(lockonVesting),
            validator,
            address(lockToken),
            2000, // start at 2000th second
            10_000_000,
            2,
            10
        );
        // Using account one
        vm.startPrank(accountOne);
        lockonVesting.setLockStakingContract(address(lockStaking));
        uint256 lockAmount = 1 ether;
        // On few second at the beginning, staking not start
        vm.expectRevert("Lock Staking: Staking not start");
        lockStaking.addLockToken(lockAmount, 200 days);
        // Increase 1 block
        vm.roll(block.number + 1);
        // Fail when lock amount = 0
        vm.expectRevert("Lock Staking: Locked amount must be greater than 0");
        lockStaking.addLockToken(0, 200 days);
        // Lock duration smaller than minimum
        lockToken.approve(address(lockStaking), 2 ether);
        vm.expectRevert("Lock Staking: Minimum lock duration does not meet");
        lockStaking.addLockToken(lockAmount, 50 days);
        skip(19 days);
        lockStaking.addLockToken(lockAmount, 200 days);
        skip(10 days);
        vm.expectRevert("Lock Staking: Invalid lock duration");
        lockStaking.addLockToken(lockAmount, 100 days);
    }

    function test_add_lock_token_fail_lock_duration() public {
        initilizeAndConfig();
        // Using account one
        vm.startPrank(accountOne);
        uint256 lockAmount = 1 ether;
        lockToken.approve(address(lockStaking), 1 ether);
        lockStaking.addLockToken(lockAmount, 101 days);
        vm.expectRevert("Lock Staking: Invalid lock duration");
        lockStaking.addLockToken(lockAmount, 100 days);
    }

    function test_extend_lock_duration() public {
        initilizeAndConfig();
        // Using account one
        vm.startPrank(accountOne);
        uint256 lockAmount = 1 ether;
        lockToken.approve(address(lockStaking), 1 ether);
        // Lock one Lock Token for 200 days
        lockStaking.addLockToken(lockAmount, 200 days);
        // Increase 30 days
        skip(30 days);
        (
            uint256 lockedAmount,
            uint256 lockScore,
            uint256 lockDuration,
            uint256 lastBasicRate,
            uint256 rewardDebt,
            uint256 lastLockedTimestamp
        ) = lockStaking.userInfo(accountOne);
        uint256 totalLockScore = lockStaking.totalLockScore();
        uint256 userLockScore = lockScore;
        assertEq(lockedAmount, lockAmount);
        // Extend the lock to 300 days
        vm.recordLogs();
        lockStaking.extendLockDuration(300 days);
        // Increase 1 block
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // Get account one extend lock data
        (lockedAmount, lockScore, lockDuration, lastBasicRate, rewardDebt, lastLockedTimestamp) =
            lockStaking.userInfo(accountOne);
        // lockedAmount does not change because it is just extend lock duration
        assertEq(lockedAmount, lockAmount);
        uint256 userLockScoreAfter =
            ((lockAmount * lastBasicRate) * lockStaking.durationRate(300 days)) / 1e12 / lockStaking.PRECISION();
        assertEq(lockScore, userLockScoreAfter);
        assertEq(lockStaking.totalLockScore(), totalLockScore - userLockScore + userLockScoreAfter);
        assertEq(lockStaking.totalLockedAmount(), lockAmount);
        // Lock duration should be 300 days
        assertEq(lockDuration, 300 days);
        assertEq(lastBasicRate, 1e12 + (30 days * lockStaking.basicRateDivider() * 1e12) / lockStaking.PRECISION());
        console.log(rewardDebt);
        assertEq(rewardDebt, (userLockScoreAfter * lockStaking.rewardPerScore()) / 1e12);
        // Check for emitted event
        assertEq(entries[3].topics[0], keccak256("ExtendLockDuration(address,uint256,uint256,uint256,uint256)"));
    }

    function test_extend_lock_duration_fail() public {
        initilizeAndConfig();
        // Using account one
        vm.startPrank(accountOne);
        // Nothing to extend
        vm.expectRevert("Lock Staking: Nothing to extend");
        lockStaking.extendLockDuration(100 days);
        uint256 lockAmount = 1 ether;
        // Lock one Lock Token for 200 days
        vm.recordLogs();
        lockToken.approve(address(lockStaking), 1 ether);
        lockStaking.addLockToken(lockAmount, 200 days);
        // New lock duration must be greater than current duration
        vm.expectRevert("Lock Staking: Invalid lock duration");
        lockStaking.extendLockDuration(100 days);
        vm.expectRevert("Lock Staking: Minimum lock duration does not meet");
        lockStaking.extendLockDuration(80 days);
        // Cannot extend duration after withdraw
        lockStaking.withdrawLockToken(1 ether);
        vm.expectRevert("Lock Staking: Nothing to extend");
        lockStaking.extendLockDuration(201 days);
    }

    function test_withdraw_lock_token() public {
        initilizeAndConfig();
        // Using account one
        vm.startPrank(accountOne);
        uint256 lockAmount = 1 ether;
        lockToken.approve(address(lockStaking), 1 ether);
        // Lock one Lock Token for 200 days and then withdraw after 10 days
        // Should be charge 30% as penalty fee and transfer it to validator address
        lockStaking.addLockToken(lockAmount, 200 days);
        (, uint256 lockScore,,,,) = lockStaking.userInfo(accountOne);
        skip(10 days);
        uint256 validatorBalanceBefore = lockToken.balanceOf(validator);
        uint256 accountOneBalanceBefore = lockToken.balanceOf(accountOne);
        vm.recordLogs();
        assertEq(lockStaking.totalLockScore(), lockScore);
        assertEq(lockStaking.totalLockedAmount(), lockAmount);
        lockStaking.withdrawLockToken(lockAmount);
        assertEq(lockStaking.totalLockScore(), 0);
        assertEq(lockStaking.totalLockedAmount(), 0);
        uint256 penaltyFee = (lockAmount * lockStaking.penaltyRate()) / lockStaking.PRECISION();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 validatorBalanceAfter = lockToken.balanceOf(validator);
        uint256 accountOneBalanceAfter = lockToken.balanceOf(accountOne);
        assertEq(validatorBalanceAfter, validatorBalanceBefore + penaltyFee);
        assertEq(accountOneBalanceAfter, accountOneBalanceBefore + lockAmount - penaltyFee);
        // Check for emitted event, since the penalty is applied, there will be 7 more event emitted before the withdraw event is emitted
        assertEq(entries[5].topics[0], keccak256("WithdrawLockToken(address,uint256,uint256,uint256)"));
        // Lock another one Lock Token and then skip 200 days
        lockToken.approve(address(lockStaking), 1 ether);
        lockStaking.addLockToken(lockAmount, 200 days);
        // With 190 days left from first lock, total 390 days
        skip(390 days);
        // This time should be able to withdraw full amount of tokens that were locked
        lockStaking.withdrawLockToken(lockAmount);
        uint256 nextValidatorBalanceAfter = lockToken.balanceOf(validator);
        assertEq(lockStaking.totalLockScore(), 0);
        assertEq(lockStaking.totalLockedAmount(), 0);
        assertEq(lockToken.balanceOf(accountOne), accountOneBalanceAfter);
        // no penalty fee
        assertEq(nextValidatorBalanceAfter, validatorBalanceAfter);
        // Lock the smallest amount of Lock Token and then claim immediately
        lockToken.approve(address(lockStaking), 1);
        lockStaking.addLockToken(1, 300 days);
        lockStaking.withdrawLockToken(1);
    }

    function test_withdraw_lock_token_fail() public {
        initilizeAndConfig();
        // User not lock any Lock Token but still call to withdraw
        vm.startPrank(accountOne);
        vm.expectRevert("Lock Staking: Nothing to withdraw");
        lockStaking.withdrawLockToken(1);
        // Withdraw more than locked amount
        lockToken.approve(address(lockStaking), 1 ether);
        lockStaking.addLockToken(1 ether, 200 days);
        vm.expectRevert("Lock Staking: Withdraw amount must be greater than 0");
        lockStaking.withdrawLockToken(0);
        vm.expectRevert("Lock Staking: Withdraw amount exceed available");
        lockStaking.withdrawLockToken(10 ether);
    }

    function test_claim_pending_reward() public {
        initilizeAndConfig();
        uint256 lockAmount = 10 ether;
        vm.startPrank(accountOne);
        lockToken.approve(address(lockStaking), lockAmount);
        lockStaking.addLockToken(lockAmount, 100 days);
        skip(100 days);
        vm.recordLogs();
        uint256 lockonVestingBalanceBefore = lockToken.balanceOf(address(lockonVesting));
        uint256 pendingReward = lockStaking.pendingReward(accountOne);
        lockStaking.claimPendingReward();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(lockToken.balanceOf(address(lockonVesting)), lockonVestingBalanceBefore + pendingReward);
        assertEq(entries[3].topics[0], keccak256("ClaimLockStakingReward(address,uint256,uint256)"));
    }

    function test_claim_pending_reward_fail() public {
        initilizeAndConfig();
        // User not lock any Lock Token but still call to claim
        vm.prank(accountOne);
        vm.expectRevert("Lock Staking: Current score is zero");
        lockStaking.claimPendingReward();
    }

    function test_set_fee_receiver_address() public {
        initilizeAndConfig();
        vm.prank(owner);
        lockStaking.setFeeReceiver(accountOne);
        assertEq(lockStaking.feeReceiver(), accountOne);
    }

    function test_set_fee_receiver_address_fail() public {
        initilizeAndConfig();
        vm.prank(accountOne);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, accountOne));
        lockStaking.setFeeReceiver(accountOne);
        vm.expectRevert("Lock Staking: Zero address not allowed");
        vm.prank(owner);
        lockStaking.setFeeReceiver(address(0));
    }

    function test_set_lockon_vesting_address() public {
        initilizeAndConfig();
        vm.prank(owner);
        lockStaking.setLockonVesting(accountOne);
        assertEq(lockStaking.lockonVesting(), accountOne);
    }

    function test_set_lockon_vesting_address_fail() public {
        initilizeAndConfig();
        vm.prank(accountOne);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, accountOne));
        lockStaking.setLockonVesting(accountOne);
        vm.expectRevert("Lock Staking: Zero address not allowed");
        vm.prank(owner);
        lockStaking.setLockonVesting(address(0));
    }

    function test_set_functions() public {
        initilizeAndConfig();
        vm.startPrank(owner);
        lockStaking.setBasicRateDivider(5);
        assertEq(lockStaking.basicRateDivider(), 5);
        lockStaking.setBonusRatePerSecond(2);
        assertEq(lockStaking.bonusRatePerSecond(), 2);
        lockStaking.setMinimumLockDuration(35600);
        assertEq(lockStaking.minimumLockDuration(), 35600);
        lockStaking.setPenaltyRate(2000);
        assertEq(lockStaking.penaltyRate(), 2000);
    }

    function test_view_function() public {
        initilizeAndConfig();
        vm.startPrank(owner);
        uint256 basicRate = lockStaking.basicRate();
        assertEq(
            basicRate,
            1e12
                + ((block.timestamp - lockStaking.lockTokenReleasedTimestamp()) * lockStaking.basicRateDivider() * 1e12)
                    / lockStaking.PRECISION()
        );
        uint256 rate = lockStaking.durationRate(1 days);
        assertEq(rate, 0);
        rate = lockStaking.durationRate(101 days);
        assertEq(rate, 1e12);
        rate = lockStaking.durationRate(300 days);
        assertEq(rate, 3.5e12);
        rate = lockStaking.durationRate(601 days);
        assertEq(rate, 8e12);
        rate = lockStaking.durationRate(1001 days);
        assertEq(rate, 16e12);
        lockStaking.rewardTokenPerSecond();
        lockStaking.getRewardMultiplier(100, 1000);
        lockStaking.getRewardMultiplier(1, 100000 days);
    }

    function test_update_pool_failed() public {
        lockonVesting.initialize(accountOne, address(lockToken));
        lockStaking.initialize(
            owner,
            address(lockonVesting),
            validator, // For testing, use validator as penalty fee receiver also
            address(lockToken),
            0,
            100000 ether,
            347300,
            1000
        );
        vm.startPrank(accountOne);
        lockToken.approve(address(lockStaking), 1000 ether);
        lockStaking.addLockToken(1000 ether, 301 days);
        vm.expectRevert("Lock Staking: Reward distributed exceed supply");
        skip(300 days);
        // Reward not transfer to contract so no reward supply
        lockStaking.updatePool();
    }

    function test_revert_on_add_vesting() public {
        lockonVesting.initialize(accountOne, address(lockToken));
        lockStaking.initialize(
            owner,
            address(lockonVesting),
            validator, // For testing, use validator as penalty fee receiver also
            address(lockToken),
            0,
            100000 ether,
            34730,
            2900
        );
        // Transfer lock token to contract for reward distribution
        lockToken.transfer(address(lockStaking), 100000 ether);
        // Using account one
        vm.startPrank(accountOne);
        uint256 lockAmount = 1 ether;
        lockToken.approve(address(lockStaking), lockAmount);
        // Lock one Lock Token for 200 days
        lockStaking.addLockToken(lockAmount, 200 days);
        skip(1 days);
        // Since the lock staking contract is not set, all next tx will be revert
        vm.expectRevert("Lockon Vesting: Forbidden");
        lockStaking.addLockToken(lockAmount, 200 days);
        vm.expectRevert("Lockon Vesting: Forbidden");
        lockStaking.extendLockDuration(300 days);
        vm.expectRevert("Lockon Vesting: Forbidden");
        lockStaking.withdrawLockToken(lockAmount);
        vm.expectRevert("Lockon Vesting: Forbidden");
        lockStaking.claimPendingReward();
    }

    function test_pause_and_unpause() public {
        initilizeAndConfig();
        vm.prank(owner);
        lockStaking.pause();
        // Cannot do any action when contract is paused
        vm.startPrank(accountOne);
        uint256 amount = 1 ether;
        vm.expectRevert(EnforcedPause.selector);
        lockStaking.addLockToken(amount, 200 days);
        vm.expectRevert(EnforcedPause.selector);
        lockStaking.extendLockDuration(200 days);
        vm.expectRevert(EnforcedPause.selector);
        lockStaking.withdrawLockToken(1);
        vm.expectRevert(EnforcedPause.selector);
        lockStaking.claimPendingReward();
        vm.stopPrank();
        // Transaction can be executed normal when unpause
        vm.prank(owner);
        lockStaking.unPause();
        vm.startPrank(accountOne);
        lockToken.approve(address(lockStaking), amount);
        lockStaking.addLockToken(amount, 100 days);
        (uint256 lockedAmount,, uint256 lockDuration,,,) = lockStaking.userInfo(accountOne);
        assertEq(lockedAmount, amount);
        assertEq(lockDuration, 100 days);
    }

    function test___receiver_func() public {
        initilizeAndConfig();
        vm.startPrank(owner);
        (bool sent,) = address(lockStaking).call{value: 1 ether}("");
        require(sent, "Failed to send Ether");
        assertEq(address(lockStaking).balance, 1 ether);
        payable(address(lockStaking)).transfer(1 ether);
        assertEq(address(lockStaking).balance, 2 ether);
    }
}
