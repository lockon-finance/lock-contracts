// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {LockStaking} from "../contracts/LockStaking.sol";
import {LockonVesting} from "../contracts/LockonVesting.sol";
import {LockToken} from "../contracts/LockToken.sol";
import {LockSigUtils} from "./LockSigUtil.sol";

contract LockStakingTest is Test {
    LockStaking public lockStaking;
    LockToken public lockToken;
    LockonVesting public lockonVesting;
    LockSigUtils internal sigUtils;
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
        lockStaking = new LockStaking();
        lockonVesting = new LockonVesting();
        deal(owner, 100 ether);
    }

    function initilizeAndConfig() public {
        lockonVesting.initialize(accountOne, address(lockToken));
        lockStaking.initialize(
            owner,
            address(validator),
            address(lockonVesting),
            validator, // For testing, use validator as penalty fee receiver also
            address(lockToken),
            0,
            100000 ether,
            34730,
            2900
        );
        sigUtils = new LockSigUtils(lockStaking.getDomainSeparator());
        // Transfer lock token to contract for reward distribution
        lockToken.transfer(address(lockStaking), 100000 ether);
        vm.stopPrank();
        // Approve to pay reward
        vm.prank(validator);
        lockToken.approve(address(validator), 100000 ether);
        vm.prank(accountOne);
        lockonVesting.addAddressDepositPermission(address(lockStaking));
    }

    function getSignatureFromVRS(uint8 v, bytes32 r, bytes32 s) internal pure returns (bytes memory) {
        // v ++ (length(r) + 0x80 ) ++ r ++ (length(s) + 0x80) ++ s
        // v ++ r ++ s
        return abi.encodePacked(r, s, v);
    }

    function test_add_lock_token() public {
        initilizeAndConfig();
        // Using account one
        vm.startPrank(accountOne);
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
            uint256 lockEndTimestamp,
            uint256 cumulativePendingReward
        ) = lockStaking.userInfo(accountOne);
        uint256 userLastBasicRate = 1e12;
        uint256 userLockScore =
            ((lockAmount * userLastBasicRate) * lockStaking.durationRate(200 days)) / 1e12 / lockStaking.PRECISION();
        uint256 userCumulativePendingReward =
            ((userLockScore * lockStaking.rewardPerScore()) / lockStaking.PRECISION()) - rewardDebt;
        assertEq(lockedAmount, lockAmount);
        assertEq(lockDuration, 200 days);
        assertEq(lockScore, userLockScore);
        assertEq(lastBasicRate, userLastBasicRate);
        assertEq(lockEndTimestamp, 200 days + 1);
        assertEq(rewardDebt, (userLockScore * lockStaking.rewardPerScore()) / 1e12);
        assertEq(cumulativePendingReward, userCumulativePendingReward);
        assertEq(lockStaking.totalLockScore(), lockScore);
        assertEq(lockStaking.totalLockedAmount(), lockAmount);
        // Check for emitted event
        assertEq(entries[2].topics[0], keccak256("LockTokenAdded(address,uint256,uint256,uint256,uint256,uint256)"));
        // Skip 100 days then lock another one Lock Token
        skip(100 days);
        lockToken.approve(address(lockStaking), 1 ether);
        lockStaking.addLockToken(lockAmount, 300 days);
        // Get account one second lock data
        (lockedAmount, lockScore, lockDuration, lastBasicRate, rewardDebt, lockEndTimestamp,) =
            lockStaking.userInfo(accountOne);
        assertEq(lockToken.balanceOf(accountOne), accountOneBalanceAfterFirstLock - lockAmount);
        userLastBasicRate = 1e12 + (100 days * lockStaking.basicRateDivider() * 1e12) / lockStaking.PRECISION();
        userLockScore =
            ((lockedAmount * userLastBasicRate) * lockStaking.durationRate(300 days)) / 1e12 / lockStaking.PRECISION();
        userCumulativePendingReward = getCumulativeOfUser(lockStaking, accountOne)
            + ((userLockScore * lockStaking.rewardPerScore()) / lockStaking.PRECISION()) - rewardDebt;
        assertEq(lockedAmount, lockAmount * 2);
        assertEq(lockScore, userLockScore);
        assertEq(lockDuration, 300 days);
        assertEq(lastBasicRate, userLastBasicRate);
        assertEq(lockEndTimestamp, (300 days + 200 days - 100 days) + 1);
        assertEq(lockStaking.totalLockScore(), userLockScore);
        assertEq(lockStaking.totalLockedAmount(), lockAmount * 2);
        assertEq(getCumulativeOfUser(lockStaking, accountOne), userCumulativePendingReward);
    }

    function test_add_lock_token_fail() public {
        lockonVesting.initialize(accountOne, address(lockToken));
        lockStaking.initialize(
            owner,
            validator, // validator to check and sign signature
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
        lockonVesting.addAddressDepositPermission(address(lockStaking));
        // On few second at the beginning, staking not start
        vm.expectRevert("LOCK Staking: Staking not start");
        lockStaking.addLockToken(lockAmount, 200 days);
        // Increase 1 block
        vm.roll(block.number + 1);
        // Fail when lock amount = 0
        vm.expectRevert("LOCK Staking: Locked amount must be greater than 0");
        lockStaking.addLockToken(0, 200 days);
        // Lock duration smaller than minimum
        lockToken.approve(address(lockStaking), 2 ether);
        vm.expectRevert("LOCK Staking: Minimum lock duration does not meet");
        lockStaking.addLockToken(lockAmount, 50 days);
        skip(19 days);
        lockStaking.addLockToken(lockAmount, 200 days);
        skip(10 days);
        vm.expectRevert("LOCK Staking: Invalid lock duration");
        lockStaking.addLockToken(lockAmount, 100 days);
    }

    function test_add_lock_token_fail_lock_duration() public {
        initilizeAndConfig();
        // Using account one
        vm.startPrank(accountOne);
        lockToken.approve(address(lockStaking), 1 ether);
        lockStaking.addLockToken(lockAmount, 101 days);
        vm.expectRevert("LOCK Staking: Invalid lock duration");
        lockStaking.addLockToken(lockAmount, 100 days);
    }

    function test_extend_lock_duration() public {
        initilizeAndConfig();
        // Using account one
        vm.startPrank(accountOne);
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
            uint256 lastLockedTimestamp,
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
        (lockedAmount, lockScore, lockDuration, lastBasicRate,, lastLockedTimestamp,) = lockStaking.userInfo(accountOne);

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
        assertEq(getRewardDebtOfUser(lockStaking, accountOne), (lockScore * lockStaking.rewardPerScore()) / 1e12);
        // Cumulative pending reward should be updated
        assertEq(
            getCumulativeOfUser(lockStaking, accountOne),
            calculateCumulatePendingReward(
                userLockScore, lockStaking.rewardPerScore(), lockStaking.PRECISION(), rewardDebt
            )
        );
        // Check for emitted event
        assertEq(entries[2].topics[0], keccak256("ExtendLockDuration(address,uint256,uint256,uint256,uint256)"));
    }

    function test_extend_lock_duration_fail() public {
        initilizeAndConfig();
        // Using account one
        vm.startPrank(accountOne);
        // Nothing to extend
        vm.expectRevert("LOCK Staking: Nothing to extend");
        lockStaking.extendLockDuration(100 days);
        // Lock one Lock Token for 200 days
        vm.recordLogs();
        lockToken.approve(address(lockStaking), 1 ether);
        lockStaking.addLockToken(lockAmount, 200 days);
        // New lock duration must be greater or equal 100 days
        vm.expectRevert("LOCK Staking: Minimum lock duration does not meet");
        lockStaking.extendLockDuration(80 days);
        // New lock duration must be greater than current duration
        vm.expectRevert("LOCK Staking: Invalid lock duration");
        lockStaking.extendLockDuration(100 days);
        // Cannot extend duration after withdraw
        lockStaking.withdrawLockToken(1 ether);
        vm.expectRevert("LOCK Staking: Nothing to extend");
        lockStaking.extendLockDuration(201 days);
    }

    function test_withdraw_lock_token() public {
        initilizeAndConfig();
        // Using account one
        vm.startPrank(accountOne);
        lockToken.approve(address(lockStaking), 1 ether);
        // Lock one Lock Token for 200 days and then withdraw after 10 days
        // Should be charge 30% as penalty fee and transfer it to validator address
        lockStaking.addLockToken(lockAmount, 200 days);
        (, uint256 lockScore,,, uint256 rewardDebt,, uint256 cumulativePendingReward) = lockStaking.userInfo(accountOne);
        skip(10 days);
        uint256 validatorBalanceBefore = lockToken.balanceOf(validator);
        uint256 accountOneBalanceBefore = lockToken.balanceOf(accountOne);
        vm.recordLogs();
        assertEq(lockStaking.totalLockScore(), lockScore);
        assertEq(lockStaking.totalLockedAmount(), lockAmount);
        lockStaking.withdrawLockToken(lockAmount);
        uint256 userCumulativePendingReward =
            (lockScore * lockStaking.rewardPerScore()) / lockStaking.PRECISION() - rewardDebt;
        (, lockScore,,, rewardDebt,, cumulativePendingReward) = lockStaking.userInfo(accountOne);
        assertEq(lockStaking.totalLockScore(), 0);
        assertEq(lockStaking.totalLockedAmount(), 0);
        assertEq(cumulativePendingReward, userCumulativePendingReward);
        uint256 penaltyFee = (lockAmount * lockStaking.penaltyRate()) / lockStaking.PRECISION();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 validatorBalanceAfter = lockToken.balanceOf(validator);
        uint256 accountOneBalanceAfter = lockToken.balanceOf(accountOne);
        assertEq(validatorBalanceAfter, validatorBalanceBefore + penaltyFee);
        assertEq(accountOneBalanceAfter, accountOneBalanceBefore + lockAmount - penaltyFee);
        // Check for emitted event, since the penalty is applied, there will be 7 more event emitted before the withdraw event is emitted
        assertEq(entries[4].topics[0], keccak256("WithdrawLockToken(address,uint256,uint256,uint256)"));
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
        vm.expectRevert("LOCK Staking: Nothing to withdraw");
        lockStaking.withdrawLockToken(1);
        // Withdraw more than locked amount
        lockToken.approve(address(lockStaking), 1 ether);
        lockStaking.addLockToken(1 ether, 200 days);
        vm.expectRevert("LOCK Staking: Withdraw amount must be greater than 0");
        lockStaking.withdrawLockToken(0);
        vm.expectRevert("LOCK Staking: Withdraw amount exceed available");
        lockStaking.withdrawLockToken(10 ether);
    }

    function test_set_validator_fail() public {
        lockonVesting.initialize(accountOne, address(lockToken));
        lockStaking.initialize(
            owner,
            validator, // validator to check and sign signature
            address(lockonVesting),
            validator, // For testing, use validator as penalty fee receiver also
            address(lockToken),
            0,
            100000 ether,
            347300,
            1000
        );
        vm.startPrank(owner);
        vm.expectRevert("LOCK Staking: Zero address not allowed");
        // Set validator address
        lockStaking.setValidatorAddress(address(0));
    }

    function test_claim_pending_reward() public {
        initilizeAndConfig();
        uint256 lockAmountLocal = 10 ether;
        uint256 rewardAmount = 20 ether;
        string memory requestId = "lockStakingClaimOrder#1";
        LockSigUtils.ClaimRequest memory claimRequest =
            LockSigUtils.ClaimRequest({requestId: requestId, beneficiary: accountOne, rewardAmount: rewardAmount});
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPrivateKey, digest);
        bytes memory signature = getSignatureFromVRS(v, r, s);
        // Using account one with generated signature from validator address to claim reward
        vm.startPrank(accountOne);
        lockToken.approve(address(lockStaking), lockAmountLocal);
        lockStaking.addLockToken(lockAmountLocal, 100 days);
        skip(100 days);
        uint256 lockonVestingBalanceBefore = lockToken.balanceOf(address(lockonVesting));
        uint256 pendingReward = lockStaking.pendingReward(accountOne);
        vm.recordLogs();
        lockStaking.claimPendingReward(requestId, rewardAmount, signature);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(lockToken.balanceOf(address(lockonVesting)), lockonVestingBalanceBefore + pendingReward + rewardAmount);
        assertEq(entries[4].topics[0], keccak256("ClaimLockStakingReward(address,string,uint256,uint256,uint256)"));
    }

    function test_claim_pending_reward_fail() public {
        initilizeAndConfig();
        uint256 lockAmountLocal = 10 ether;
        uint256 rewardAmount = 20 ether;
        string memory requestId = "lockStakingClaimOrder#1";
        LockSigUtils.ClaimRequest memory claimRequest =
            LockSigUtils.ClaimRequest({requestId: requestId, beneficiary: accountOne, rewardAmount: rewardAmount});
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPrivateKey, digest);
        bytes memory signature = getSignatureFromVRS(v, r, s);
        // Using account one with generated signature from validator address to claim reward
        vm.startPrank(accountOne);
        vm.expectRevert("LOCK Staking: Nothing to claim");
        lockStaking.claimPendingReward(requestId, rewardAmount, signature);
        lockToken.approve(address(lockStaking), lockAmountLocal);
        lockStaking.addLockToken(lockAmountLocal, 100 days);
        skip(100 days);
        vm.expectRevert("LOCK Staking: Invalid signature");
        lockStaking.claimPendingReward(requestId, rewardAmount + 1, signature);

        lockStaking.claimPendingReward(requestId, rewardAmount, signature);
        vm.expectRevert("LOCK Staking: Request already processed");
        lockStaking.claimPendingReward(requestId, rewardAmount, signature);
    }

    function test_set_fee_receiver_address() public {
        initilizeAndConfig();
        vm.prank(owner);
        vm.recordLogs();
        lockStaking.setFeeReceiver(accountOne);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(lockStaking.feeReceiver(), accountOne);
        assertEq(entries[0].topics[0], keccak256("FeeReceiverUpdated(address,uint256)"));
    }

    function test_set_fee_receiver_address_fail() public {
        initilizeAndConfig();
        vm.prank(accountOne);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, accountOne));
        lockStaking.setFeeReceiver(accountOne);
        vm.expectRevert("LOCK Staking: Zero address not allowed");
        vm.prank(owner);
        lockStaking.setFeeReceiver(address(0));
    }

    function test_set_lockon_vesting_address() public {
        initilizeAndConfig();
        vm.prank(owner);
        vm.recordLogs();
        lockStaking.setLockonVesting(accountOne);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(lockStaking.lockonVesting(), accountOne);
        assertEq(entries[0].topics[0], keccak256("LockonVestingUpdated(address,uint256)"));
    }

    function test_set_lockon_vesting_address_fail() public {
        initilizeAndConfig();
        vm.prank(accountOne);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, accountOne));
        lockStaking.setLockonVesting(accountOne);
        vm.expectRevert("LOCK Staking: Zero address not allowed");
        vm.prank(owner);
        lockStaking.setLockonVesting(address(0));
    }

    function test_set_functions() public {
        initilizeAndConfig();
        vm.startPrank(owner);
        vm.recordLogs();
        lockStaking.setBasicRateDivider(5);
        assertEq(lockStaking.basicRateDivider(), 5);
        lockStaking.setBonusRatePerSecond(2);
        assertEq(lockStaking.bonusRatePerSecond(), 2);
        lockStaking.setMinimumLockDuration(35600);
        assertEq(lockStaking.minimumLockDuration(), 35600);
        lockStaking.setPenaltyRate(2000);
        assertEq(lockStaking.penaltyRate(), 2000);
        lockStaking.setValidatorAddress(accountTwo);
        assertEq(lockStaking.validatorAddress(), accountTwo);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("BasicRateDividerUpdated(uint256,uint256,uint256,uint256,uint256)"));
        assertEq(entries[1].topics[0], keccak256("BonusRatePerSecondUpdated(uint256,uint256,uint256,uint256,uint256)"));
        assertEq(entries[2].topics[0], keccak256("MinimumLockDurationUpdated(uint256,uint256)"));
        assertEq(entries[3].topics[0], keccak256("PenaltyRateUpdated(uint256,uint256)"));
        assertEq(entries[4].topics[0], keccak256("ValidatorAddressUpdated(address,uint256)"));
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

    function test_allocate_token() public {
        initilizeAndConfig();
        uint256 oldLockBalance = lockToken.balanceOf(address(lockStaking));
        // Using account one
        vm.startPrank(owner);
        vm.recordLogs();
        // Allocate amount of lock token
        lockToken.approve(address(lockStaking), lockAmount);
        lockStaking.allocateLockToken(lockAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[2].topics[0], keccak256("LockTokenAllocated(address,uint256)"));
        assertEq(lockToken.balanceOf(address(lockStaking)), oldLockBalance + lockAmount);
    }

    function test_update_pool_failed() public {
        lockonVesting.initialize(accountOne, address(lockToken));
        lockStaking.initialize(
            owner,
            validator, // validator to check and sign signature
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
        vm.expectRevert("LOCK Staking: Reward distributed exceed supply");
        skip(300 days);
        // Reward not transfer to contract so no reward supply
        lockStaking.updatePool();
    }

    function test_revert_on_deposit_vesting() public {
        lockonVesting.initialize(accountOne, address(lockToken));
        lockStaking.initialize(
            owner,
            validator, // validator to check and sign signature
            address(lockonVesting),
            validator, // For testing, use validator as penalty fee receiver also
            address(lockToken),
            0,
            100000 ether,
            34730,
            2900
        );
        sigUtils = new LockSigUtils(lockStaking.getDomainSeparator());

        // Initalize signature for claim reward
        uint256 rewardAmount = 20 ether;
        string memory requestId = "lockStakingClaimOrder#1";
        LockSigUtils.ClaimRequest memory claimRequest =
            LockSigUtils.ClaimRequest({requestId: requestId, beneficiary: accountOne, rewardAmount: rewardAmount});
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPrivateKey, digest);
        bytes memory signature = getSignatureFromVRS(v, r, s);
        // Transfer lock token to contract for reward distribution
        lockToken.transfer(address(lockStaking), 100000 ether);
        // Using account one
        vm.startPrank(accountOne);
        lockToken.approve(address(lockStaking), 2 * lockAmount);
        // Lock one Lock Token for 200 days
        lockStaking.addLockToken(lockAmount, 200 days);
        skip(1 days);
        lockStaking.addLockToken(lockAmount, 200 days);
        // Since the lock staking contract is not set, all next tx will be revert
        vm.expectRevert("LOCKON Vesting: Forbidden");
        lockStaking.claimPendingReward(requestId, rewardAmount, signature);
    }

    function test_cancel_claim_order() public {
        initilizeAndConfig();
        uint256 stakeAmount = 10 ether;
        uint256 rewardAmount = 1 ether;
        string memory requestId = "lockStakingClaimOrder#1";
        LockSigUtils.ClaimRequest memory claimRequest =
            LockSigUtils.ClaimRequest({requestId: requestId, beneficiary: accountOne, rewardAmount: rewardAmount});
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPrivateKey, digest);

        bytes memory signature = getSignatureFromVRS(v, r, s);
        // Using account one with generated signature
        vm.startPrank(accountOne);
        lockToken.approve(address(lockStaking), stakeAmount);
        lockStaking.addLockToken(stakeAmount, 100 days);
        vm.recordLogs();
        lockStaking.cancelClaimOrder(requestId, rewardAmount, signature);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("ClaimOrderCancel(address,string)"));
        // Make sure that the requestId cannot be claimed after cancel
        vm.expectRevert("LOCK Staking: Request already processed");
        lockStaking.claimPendingReward(requestId, rewardAmount, signature);
    }

    function test_cancel_claim_order_fail() public {
        initilizeAndConfig();
        uint256 stakeAmount = 10 ether;
        uint256 rewardAmount = 1 ether;
        string memory requestId = "lockStakingClaimOrder#1";
        LockSigUtils.ClaimRequest memory claimRequest =
            LockSigUtils.ClaimRequest({requestId: requestId, beneficiary: accountOne, rewardAmount: rewardAmount});
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPrivateKey, digest);

        bytes memory signature = getSignatureFromVRS(v, r, s);
        // User not stake any Lock Token but still call to cancel claim
        vm.prank(accountOne);
        vm.expectRevert("LOCK Staking: User hasn't staked any token yet");
        lockStaking.cancelClaimOrder(requestId, rewardAmount, signature);
        // Account two using signature that is generated for account one
        vm.startPrank(accountTwo);
        lockToken.approve(address(lockStaking), stakeAmount);
        lockStaking.addLockToken(stakeAmount, 100 days);
        vm.expectRevert("LOCK Staking: Invalid signature");
        lockStaking.cancelClaimOrder(requestId, rewardAmount, signature);
        // Reward that already claimed cannot be cancelled
        vm.startPrank(accountOne);
        lockToken.approve(address(lockStaking), stakeAmount);
        lockStaking.addLockToken(stakeAmount, 100 days);
        lockStaking.claimPendingReward(requestId, rewardAmount, signature);
        vm.expectRevert("LOCK Staking: Request already processed");
        lockStaking.cancelClaimOrder(requestId, rewardAmount, signature);
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
        uint256 rewardAmount = 20 ether;
        string memory requestId = "indexStakingClaimOrder#1";
        LockSigUtils.ClaimRequest memory claimRequest =
            LockSigUtils.ClaimRequest({requestId: requestId, beneficiary: accountOne, rewardAmount: rewardAmount});
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPrivateKey, digest);
        bytes memory signature = getSignatureFromVRS(v, r, s);
        vm.expectRevert(EnforcedPause.selector);
        lockStaking.claimPendingReward(requestId, rewardAmount, signature);
        vm.stopPrank();
        // Transaction can be executed normal when unpause
        vm.prank(owner);
        lockStaking.unPause();
        vm.startPrank(accountOne);
        lockToken.approve(address(lockStaking), amount);
        lockStaking.addLockToken(amount, 100 days);
        (uint256 lockedAmount,, uint256 lockDuration,,,,) = lockStaking.userInfo(accountOne);
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

    function getCumulativeOfUser(LockStaking lockStakingContract, address account) public view returns (uint256) {
        (,,,,,, uint256 cumulativePendingReward) = lockStakingContract.userInfo(account);
        return cumulativePendingReward;
    }

    function getRewardDebtOfUser(LockStaking lockStakingContract, address account) public view returns (uint256) {
        (,,,, uint256 rewardDebt,,) = lockStakingContract.userInfo(account);
        return rewardDebt;
    }

    function calculateCumulatePendingReward(
        uint256 lockScore,
        uint256 rewardPerScore,
        uint256 precision,
        uint256 rewardDebt
    ) public pure returns (uint256) {
        return ((lockScore * rewardPerScore) / precision) - rewardDebt;
    }

    function test_get_signer_for_request() public {
        initilizeAndConfig();
        uint256 rewardAmount = 10 ether;
        string memory requestId = "lockStakingClaimOrder#1";
        LockSigUtils.ClaimRequest memory claimRequest =
            LockSigUtils.ClaimRequest({requestId: requestId, beneficiary: accountOne, rewardAmount: rewardAmount});
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPrivateKey, digest);

        bytes memory signature = getSignatureFromVRS(v, r, s);
        // Using account one with generated signature
        vm.startPrank(accountOne);
        lockToken.approve(address(lockStaking), lockAmount);
        lockStaking.addLockToken(lockAmount, 100 days);
        skip(100 days);
        address signer = lockStaking.getSignerForRequest(requestId, accountOne, rewardAmount, signature);
        assertEq(signer, validator);
    }
}
