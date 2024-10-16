// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {LockStaking} from "../contracts/LockStaking.sol";
import {LockonVesting} from "../contracts/LockonVesting.sol";
import {LockToken} from "../contracts/LockToken.sol";
import {LockSigUtils} from "./LockSigUtil.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract LockStakingTest is Test {
    LockStaking public lockStaking;
    LockToken public lockToken;
    LockonVesting public lockonVesting;
    LockSigUtils internal sigUtils;
    ERC1967Proxy tokenProxy;
    ERC1967Proxy lockonVestingProxy;
    ERC1967Proxy lockStakingProxy;
    uint256[] vestingCategoryIds;
    uint256[] vestingPeriods;
    uint256 constant VALIDATOR_PRIVATE_KEY = 123;
    address public constant OWNER = address(bytes20(bytes("OWNER")));
    address public constant ACCOUNT_ONE = address(1);
    address public constant ACCOUNT_TWO = address(2);
    address public validator = vm.addr(VALIDATOR_PRIVATE_KEY);
    uint256 public constant TEST_ACCOUNT_INITIAL_LOCK_BALANCE = 1000 ether;
    uint256 lockAmount = 1 ether;
    uint256 private constant PRECISION = 1e12;

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
        lockStaking = new LockStaking();
        lockonVesting = new LockonVesting();
        deal(OWNER, 100 ether);
        vestingCategoryIds = new uint256[](1);
        vestingCategoryIds[0] = 0;
        vestingPeriods = new uint256[](1);
        vestingPeriods[0] = 300 days;
    }

    function initializeAndConfig() public {
        bytes memory lockonVestingData = abi.encodeCall(lockonVesting.initialize, (ACCOUNT_ONE, address(lockToken), vestingCategoryIds, vestingPeriods));
        lockonVestingProxy = new ERC1967Proxy(address(lockonVesting), lockonVestingData);
        lockonVesting = LockonVesting(address(lockonVestingProxy));
        bytes memory lockStakingData = abi.encodeCall(
            lockStaking.initialize,
            (
                OWNER,
                validator, // For testing, use validator as penalty fee receiver also
                address(lockonVesting),
                validator, // For testing, use validator as penalty fee receiver also
                address(lockToken),
                0,
                100000 ether,
                34730,
                2900
            )
        );
        lockStakingProxy = new ERC1967Proxy(address(lockStaking), lockStakingData);
        lockStaking = LockStaking(address(lockStakingProxy));
        sigUtils = new LockSigUtils(lockStaking.getDomainSeparator());
        // Transfer LOCK token to contract for reward distribution
        lockToken.transfer(address(lockStaking), 100000 ether);
        vm.stopPrank();
        // Approve to pay reward
        vm.prank(validator);
        lockToken.approve(validator, 100000 ether);
        vm.prank(ACCOUNT_ONE);
        lockonVesting.addAddressDepositPermission(address(lockStaking));
    }

    function getSignatureFromVRS(uint8 v, bytes32 r, bytes32 s) internal pure returns (bytes memory) {
        // v ++ (length(r) + 0x80 ) ++ r ++ (length(s) + 0x80) ++ s
        // v ++ r ++ s
        return abi.encodePacked(r, s, v);
    }

    function test_initialize_fail_bonus_rate() public {
        vm.expectRevert("LOCK Staking: Bonus rate per second must be greater than 0");
        bytes memory lockStakingData = abi.encodeCall(
            lockStaking.initialize,
            (
                OWNER,
                validator, // For testing, use validator as penalty fee receiver also
                address(lockonVesting),
                validator, // For testing, use validator as penalty fee receiver also
                address(lockToken),
                0,
                100000 ether,
                34730,
                0
            )
        );
        lockStakingProxy = new ERC1967Proxy(address(lockStaking), lockStakingData);
        lockStaking = LockStaking(address(lockStakingProxy));
    }

    function test_initialize_fail_owner_zero_address() public {
        vm.expectRevert("LOCK Staking: owner is the zero address");
        bytes memory lockStakingData = abi.encodeCall(
            lockStaking.initialize,
            (
                address(0),
                validator, // For testing, use validator as penalty fee receiver also
                address(lockonVesting),
                validator, // For testing, use validator as penalty fee receiver also
                address(lockToken),
                0,
                100000 ether,
                34730,
                10
            )
        );
        lockStakingProxy = new ERC1967Proxy(address(lockStaking), lockStakingData);
        lockStaking = LockStaking(address(lockStakingProxy));
    }

    function test_initialize_fail_validator_zero_address() public {
        vm.expectRevert("LOCK Staking: validator is the zero address");
        bytes memory lockStakingData = abi.encodeCall(
            lockStaking.initialize,
            (
                OWNER,
                address(0),
                address(lockonVesting),
                validator, // For testing, use validator as penalty fee receiver also
                address(lockToken),
                0,
                100000 ether,
                34730,
                10
            )
        );
        lockStakingProxy = new ERC1967Proxy(address(lockStaking), lockStakingData);
        lockStaking = LockStaking(address(lockStakingProxy));
    }

    function test_initialize_fail_lockon_vesting_zero_address() public {
        vm.expectRevert("LOCK Staking: lockonVesting is the zero address");
        bytes memory lockStakingData = abi.encodeCall(
            lockStaking.initialize,
            (
                OWNER,
                validator, // For testing, use validator as penalty fee receiver also
                address(0),
                validator, // For testing, use validator as penalty fee receiver also
                address(lockToken),
                0,
                100000 ether,
                34730,
                10
            )
        );
        lockStakingProxy = new ERC1967Proxy(address(lockStaking), lockStakingData);
        lockStaking = LockStaking(address(lockStakingProxy));
    }

    function test_initialize_fail_fee_receiver_zero_address() public {
        vm.expectRevert("LOCK Staking: feeReceiver is the zero address");
        bytes memory lockStakingData = abi.encodeCall(
            lockStaking.initialize,
            (
                OWNER,
                validator, // For testing, use validator as penalty fee receiver also
                address(lockonVesting),
                address(0), // For testing, use validator as penalty fee receiver also
                address(lockToken),
                0,
                100000 ether,
                34730,
                10
            )
        );
        lockStakingProxy = new ERC1967Proxy(address(lockStaking), lockStakingData);
        lockStaking = LockStaking(address(lockStakingProxy));
    }

    function test_initialize_fail_lock_token_zero_address() public {
        vm.expectRevert("LOCK Staking: lockToken is the zero address");
        bytes memory lockStakingData = abi.encodeCall(
            lockStaking.initialize,
            (
                OWNER,
                validator, // For testing, use validator as penalty fee receiver also
                address(lockonVesting),
                validator, // For testing, use validator as penalty fee receiver also
                address(0),
                0,
                100000 ether,
                34730,
                10
            )
        );
        lockStakingProxy = new ERC1967Proxy(address(lockStaking), lockStakingData);
        lockStaking = LockStaking(address(lockStakingProxy));
    }

    function test_add_lock_token() public {
        initializeAndConfig();
        // Using account one
        vm.startPrank(ACCOUNT_ONE);
        lockToken.approve(address(lockStaking), 1 ether);
        // Lock one Lock Token for 200 days
        lockStaking.addLockToken(lockAmount, 200 days);
        uint256 ACCOUNT_ONEBalanceAfterFirstLock = TEST_ACCOUNT_INITIAL_LOCK_BALANCE - lockAmount;
        assertEq(lockToken.balanceOf(ACCOUNT_ONE), ACCOUNT_ONEBalanceAfterFirstLock);
        // Get account one first lock data
        (
            uint256 lockedAmount,
            uint256 lockScore,
            uint256 lockDuration,
            uint256 lastBasicRate,
            uint256 rewardDebt,
            uint256 lockEndTimestamp,
            uint256 cumulativePendingReward
        ) = lockStaking.userInfo(ACCOUNT_ONE);
        uint256 userLastBasicRate = 1e12;
        uint256 userLockScore =
            ((lockAmount * userLastBasicRate) * lockStaking.durationRate(200 days)) / 1e12 / PRECISION;
        uint256 userCumulativePendingReward = ((userLockScore * lockStaking.rewardPerScore()) / PRECISION) - rewardDebt;
        assertEq(lockedAmount, lockAmount);
        assertEq(lockDuration, 200 days);
        assertEq(lockScore, userLockScore);
        assertEq(lastBasicRate, userLastBasicRate);
        assertEq(lockEndTimestamp, 200 days + 1);
        assertEq(rewardDebt, (userLockScore * lockStaking.rewardPerScore()) / 1e12);
        assertEq(cumulativePendingReward, userCumulativePendingReward);
        assertEq(lockStaking.totalLockScore(), lockScore);
        assertEq(lockStaking.totalLockedAmount(), lockAmount);
        // Skip 100 days then lock another one Lock Token
        skip(100 days);
        vm.recordLogs();
        lockToken.approve(address(lockStaking), 1 ether);
        lockStaking.addLockToken(lockAmount, 300 days);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // Check for emitted event
        assertEq(entries[1].topics[0], keccak256("PoolDataUpdated(address,uint256,uint256,uint256)"));
        assertEq(entries[4].topics[0], keccak256("LockTokenAdded(address,uint256,uint256,uint256,uint256,uint256)"));
        // Get account one second lock data
        (lockedAmount, lockScore,, lastBasicRate, rewardDebt, lockEndTimestamp,) = lockStaking.userInfo(ACCOUNT_ONE);
        assertEq(lockToken.balanceOf(ACCOUNT_ONE), ACCOUNT_ONEBalanceAfterFirstLock - lockAmount);
        userLastBasicRate = 1e12 + (100 days * lockStaking.basicRateDivider() * 1e12) / PRECISION;
        userLockScore = ((lockedAmount * userLastBasicRate) * lockStaking.durationRate(300 days)) / 1e12 / PRECISION;
        userCumulativePendingReward = getCumulativeOfUser(lockStaking, ACCOUNT_ONE)
            + ((userLockScore * lockStaking.rewardPerScore()) / PRECISION) - rewardDebt;
        assertEq(lockedAmount, lockAmount * 2);
        assertEq(lockScore, userLockScore);
        assertEq(lastBasicRate, userLastBasicRate);
        assertEq(lockEndTimestamp, (300 days + 200 days - 100 days) + 1);
        assertEq(lockStaking.totalLockScore(), userLockScore);
        assertEq(lockStaking.totalLockedAmount(), lockAmount * 2);
        assertEq(getCumulativeOfUser(lockStaking, ACCOUNT_ONE), userCumulativePendingReward);
    }

    function test_add_lock_token_fail() public {
        bytes memory lockonVestingData = abi.encodeCall(lockonVesting.initialize, (ACCOUNT_ONE, address(lockToken), vestingCategoryIds, vestingPeriods));
        lockonVestingProxy = new ERC1967Proxy(address(lockonVesting), lockonVestingData);
        lockonVesting = LockonVesting(address(lockonVestingProxy));
        bytes memory lockStakingData = abi.encodeCall(
            lockStaking.initialize,
            (
                OWNER,
                validator, // For testing, use validator as penalty fee receiver also
                address(lockonVesting),
                validator, // For testing, use validator as penalty fee receiver also
                address(lockToken),
                2000, // start at 2000th second
                10_000_000,
                2,
                10
            )
        );
        lockStakingProxy = new ERC1967Proxy(address(lockStaking), lockStakingData);
        lockStaking = LockStaking(address(lockStakingProxy));
        // Using account one
        vm.startPrank(ACCOUNT_ONE);
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
        initializeAndConfig();
        // Using account one
        vm.startPrank(ACCOUNT_ONE);
        lockToken.approve(address(lockStaking), 1 ether);
        lockStaking.addLockToken(lockAmount, 101 days);
        vm.expectRevert("LOCK Staking: Invalid lock duration");
        lockStaking.addLockToken(lockAmount, 100 days);
    }

    function test_extend_lock_duration() public {
        initializeAndConfig();
        // Using account one
        vm.startPrank(ACCOUNT_ONE);
        lockToken.approve(address(lockStaking), 1 ether);
        // Lock one Lock Token for 200 days
        lockStaking.addLockToken(lockAmount, 200 days);
        assertEq(lockStaking.getUserLockScore(0, 10 days), 0);
        assertEq(
            lockStaking.getUserLockScore(0, 321 days),
            (((lockAmount) * lockStaking.basicRate()) * lockStaking.durationRate(321 days)) / 1e12 / PRECISION
        );
        // Increase 30 days
        skip(30 days);
        (
            uint256 lockedAmount,
            uint256 lockScore,
            uint256 lockDuration,
            uint256 lastBasicRate,
            uint256 rewardDebt,
            uint256 lastLockedTimestamp,
        ) = lockStaking.userInfo(ACCOUNT_ONE);
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
        (lockedAmount, lockScore, lockDuration, lastBasicRate,, lastLockedTimestamp,) =
            lockStaking.userInfo(ACCOUNT_ONE);

        // lockedAmount does not change because it is just extend lock duration
        assertEq(lockedAmount, lockAmount);
        uint256 userLockScoreAfter =
            ((lockAmount * lastBasicRate) * lockStaking.durationRate(300 days)) / 1e12 / PRECISION;
        assertEq(lockScore, userLockScoreAfter);
        assertEq(lockStaking.totalLockScore(), totalLockScore - userLockScore + userLockScoreAfter);
        assertEq(lockStaking.totalLockedAmount(), lockAmount);
        // Lock duration should be 300 days
        assertEq(lockDuration, 300 days);
        assertEq(lastBasicRate, 1e12 + (30 days * lockStaking.basicRateDivider() * 1e12) / PRECISION);
        assertEq(getRewardDebtOfUser(lockStaking, ACCOUNT_ONE), (lockScore * lockStaking.rewardPerScore()) / 1e12);
        // Cumulative pending reward should be updated
        assertEq(
            getCumulativeOfUser(lockStaking, ACCOUNT_ONE),
            calculateCumulatePendingReward(userLockScore, lockStaking.rewardPerScore(), PRECISION, rewardDebt)
        );
        // Check for emitted event
        assertEq(entries[0].topics[0], keccak256("PoolDataUpdated(address,uint256,uint256,uint256)"));
        assertEq(entries[2].topics[0], keccak256("ExtendLockDuration(address,uint256,uint256,uint256,uint256)"));
    }

    function test_extend_lock_duration_fail() public {
        initializeAndConfig();
        // Using account one
        vm.startPrank(ACCOUNT_ONE);
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
        initializeAndConfig();
        // Using account one
        vm.startPrank(ACCOUNT_ONE);
        lockToken.approve(address(lockStaking), 1 ether);
        // Lock one Lock Token for 200 days and then withdraw after 10 days
        // Should be charge 30% as penalty fee and transfer it to validator address
        lockStaking.addLockToken(lockAmount, 200 days);
        (, uint256 lockScore,,, uint256 rewardDebt,, uint256 cumulativePendingReward) =
            lockStaking.userInfo(ACCOUNT_ONE);
        skip(10 days);
        uint256 validatorBalanceBefore = lockToken.balanceOf(validator);
        uint256 ACCOUNT_ONEBalanceBefore = lockToken.balanceOf(ACCOUNT_ONE);
        vm.recordLogs();
        assertEq(lockStaking.totalLockScore(), lockScore);
        assertEq(lockStaking.totalLockedAmount(), lockAmount);
        lockStaking.withdrawLockToken(lockAmount);
        uint256 userCumulativePendingReward = (lockScore * lockStaking.rewardPerScore()) / PRECISION - rewardDebt;
        (, lockScore,,, rewardDebt,, cumulativePendingReward) = lockStaking.userInfo(ACCOUNT_ONE);
        assertEq(lockStaking.totalLockScore(), 0);
        assertEq(lockStaking.totalLockedAmount(), 0);
        assertEq(cumulativePendingReward, userCumulativePendingReward);
        uint256 penaltyFee = (lockAmount * lockStaking.penaltyRate()) / PRECISION;
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 validatorBalanceAfter = lockToken.balanceOf(validator);
        uint256 ACCOUNT_ONEBalanceAfter = lockToken.balanceOf(ACCOUNT_ONE);
        assertEq(validatorBalanceAfter, validatorBalanceBefore + penaltyFee);
        assertEq(ACCOUNT_ONEBalanceAfter, ACCOUNT_ONEBalanceBefore + lockAmount - penaltyFee);
        // Check for emitted event, since the penalty is applied, there will be 7 more event emitted before the withdraw event is emitted
        assertEq(entries[0].topics[0], keccak256("PoolDataUpdated(address,uint256,uint256,uint256)"));
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
        assertEq(lockToken.balanceOf(ACCOUNT_ONE), ACCOUNT_ONEBalanceAfter);
        // no penalty fee
        assertEq(nextValidatorBalanceAfter, validatorBalanceAfter);
        // Lock the smallest amount of Lock Token and then claim immediately
        lockToken.approve(address(lockStaking), 1);
        lockStaking.addLockToken(1, 300 days);
        lockStaking.withdrawLockToken(1);
    }

    function test_withdraw_lock_token_fail() public {
        initializeAndConfig();
        // User not lock any Lock Token but still call to withdraw
        vm.startPrank(ACCOUNT_ONE);
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
        bytes memory lockonVestingData = abi.encodeCall(lockonVesting.initialize, (ACCOUNT_ONE, address(lockToken), vestingCategoryIds, vestingPeriods));
        lockonVestingProxy = new ERC1967Proxy(address(lockonVesting), lockonVestingData);
        lockonVesting = LockonVesting(address(lockonVestingProxy));
        bytes memory lockStakingData = abi.encodeCall(
            lockStaking.initialize,
            (
                OWNER,
                validator, // For testing, use validator as penalty fee receiver also
                address(lockonVesting),
                validator, // For testing, use validator as penalty fee receiver also
                address(lockToken),
                0,
                100000 ether,
                347300,
                1000
            )
        );
        lockStakingProxy = new ERC1967Proxy(address(lockStaking), lockStakingData);
        lockStaking = LockStaking(address(lockStakingProxy));
        vm.startPrank(OWNER);
        vm.expectRevert("LOCK Staking: Zero address not allowed");
        // Set validator address
        lockStaking.setValidatorAddress(address(0));
    }

    function test_claim_pending_reward() public {
        initializeAndConfig();
        uint256 lockAmountLocal = 10 ether;
        uint256 rewardAmount = 20 ether;
        string memory requestId = "lockStakingClaimOrder#1";
        LockSigUtils.ClaimRequest memory claimRequest =
            LockSigUtils.ClaimRequest({requestId: requestId, beneficiary: ACCOUNT_ONE, rewardAmount: rewardAmount});
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(VALIDATOR_PRIVATE_KEY, digest);
        bytes memory signature = getSignatureFromVRS(v, r, s);
        // Using account one with generated signature from validator address to claim reward
        vm.startPrank(ACCOUNT_ONE);
        lockToken.approve(address(lockStaking), lockAmountLocal);
        lockStaking.addLockToken(lockAmountLocal, 100 days);
        skip(100 days);
        uint256 lockonVestingBalanceBefore = lockToken.balanceOf(address(lockonVesting));
        uint256 pendingReward = lockStaking.pendingReward(ACCOUNT_ONE);
        vm.recordLogs();
        lockStaking.claimPendingReward(requestId, rewardAmount, signature);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(lockToken.balanceOf(address(lockonVesting)), lockonVestingBalanceBefore + pendingReward + rewardAmount);
        assertEq(entries[0].topics[0], keccak256("PoolDataUpdated(address,uint256,uint256,uint256)"));
        assertEq(entries[4].topics[0], keccak256("ClaimLockStakingReward(address,string,uint256,uint256,uint256)"));
    }

    function test_claim_pending_reward_fail() public {
        initializeAndConfig();
        uint256 lockAmountLocal = 10 ether;
        uint256 rewardAmount = 20 ether;
        string memory requestId = "lockStakingClaimOrder#1";
        LockSigUtils.ClaimRequest memory claimRequest =
            LockSigUtils.ClaimRequest({requestId: requestId, beneficiary: ACCOUNT_ONE, rewardAmount: rewardAmount});
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(VALIDATOR_PRIVATE_KEY, digest);
        bytes memory signature = getSignatureFromVRS(v, r, s);
        // Using account one with generated signature from validator address to claim reward
        vm.startPrank(ACCOUNT_ONE);
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
        initializeAndConfig();
        vm.prank(OWNER);
        vm.recordLogs();
        lockStaking.setFeeReceiver(ACCOUNT_ONE);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(lockStaking.feeReceiver(), ACCOUNT_ONE);
        assertEq(entries[0].topics[0], keccak256("FeeReceiverUpdated(address,address,uint256)"));
    }

    function test_set_fee_receiver_address_fail() public {
        initializeAndConfig();
        vm.prank(ACCOUNT_ONE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, ACCOUNT_ONE));
        lockStaking.setFeeReceiver(ACCOUNT_ONE);
        vm.expectRevert("LOCK Staking: Zero address not allowed");
        vm.prank(OWNER);
        lockStaking.setFeeReceiver(address(0));
    }

    function test_set_lockon_vesting_address() public {
        initializeAndConfig();
        vm.prank(OWNER);
        vm.recordLogs();
        lockStaking.setLockonVesting(ACCOUNT_ONE);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(lockStaking.lockonVesting(), ACCOUNT_ONE);
        assertEq(entries[0].topics[0], keccak256("LockonVestingUpdated(address,address,uint256)"));
    }

    function test_set_lockon_vesting_address_fail() public {
        initializeAndConfig();
        vm.prank(ACCOUNT_ONE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, ACCOUNT_ONE));
        lockStaking.setLockonVesting(ACCOUNT_ONE);
        vm.expectRevert("LOCK Staking: Zero address not allowed");
        vm.prank(OWNER);
        lockStaking.setLockonVesting(address(0));
    }

    function test_set_functions() public {
        initializeAndConfig();
        vm.startPrank(OWNER);
        vm.recordLogs();
        lockStaking.setBasicRateDivider(5);
        assertEq(lockStaking.basicRateDivider(), 5);
        lockStaking.setBonusRatePerSecond(2);
        assertEq(lockStaking.bonusRatePerSecond(), 2);
        lockStaking.setMinimumLockDuration(35600);
        assertEq(lockStaking.minimumLockDuration(), 35600);
        lockStaking.setPenaltyRate(2000);
        assertEq(lockStaking.penaltyRate(), 2000);
        lockStaking.setValidatorAddress(ACCOUNT_TWO);
        assertEq(lockStaking.validatorAddress(), ACCOUNT_TWO);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(
            entries[0].topics[0], keccak256("BasicRateDividerUpdated(address,uint256,uint256,uint256,uint256,uint256)")
        );
        assertEq(
            entries[1].topics[0],
            keccak256("BonusRatePerSecondUpdated(address,uint256,uint256,uint256,uint256,uint256)")
        );
        assertEq(entries[2].topics[0], keccak256("MinimumLockDurationUpdated(address,uint256,uint256)"));
        assertEq(entries[3].topics[0], keccak256("PenaltyRateUpdated(address,uint256,uint256)"));
        assertEq(entries[4].topics[0], keccak256("ValidatorAddressUpdated(address,address,uint256)"));
    }

    function test_set_bonus_rate_per_second_fail() public {
        initializeAndConfig();
        vm.expectRevert("LOCK Staking: Bonus rate per second must be greater than 0");
        vm.prank(OWNER);
        lockStaking.setBonusRatePerSecond(0);
    }

    function test_view_function() public {
        initializeAndConfig();
        vm.startPrank(OWNER);
        uint256 basicRate = lockStaking.basicRate();
        assertEq(
            basicRate,
            1e12
                + ((block.timestamp - lockStaking.lockTokenReleasedTimestamp()) * lockStaking.basicRateDivider() * 1e12)
                    / PRECISION
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
        initializeAndConfig();
        uint256 oldLockBalance = lockToken.balanceOf(address(lockStaking));
        // Using account one
        vm.startPrank(OWNER);
        vm.recordLogs();
        // Allocate amount of LOCK token
        lockToken.approve(address(lockStaking), lockAmount);
        lockStaking.allocateLockToken(lockAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[2].topics[0], keccak256("LockTokenAllocated(address,uint256)"));
        assertEq(lockToken.balanceOf(address(lockStaking)), oldLockBalance + lockAmount);
    }

    function test_deallocate_token() public {
        initializeAndConfig();
        uint256 oldLockBalance = lockToken.balanceOf(address(lockStaking));
        // Using account one
        vm.startPrank(OWNER);
        vm.recordLogs();
        // Deallocate amount of LOCK token
        lockToken.approve(address(lockStaking), lockAmount);
        lockStaking.deallocateLockToken(lockAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[2].topics[0], keccak256("LockTokenDeallocated(address,uint256)"));
        assertEq(lockToken.balanceOf(address(lockStaking)), oldLockBalance - lockAmount);
    }

    function test_revert_on_deposit_vesting() public {
        bytes memory lockonVestingData = abi.encodeCall(lockonVesting.initialize, (ACCOUNT_ONE, address(lockToken), vestingCategoryIds, vestingPeriods));
        lockonVestingProxy = new ERC1967Proxy(address(lockonVesting), lockonVestingData);
        lockonVesting = LockonVesting(address(lockonVestingProxy));
        bytes memory lockStakingData = abi.encodeCall(
            lockStaking.initialize,
            (
                OWNER,
                validator, // For testing, use validator as penalty fee receiver also
                address(lockonVesting),
                validator, // For testing, use validator as penalty fee receiver also
                address(lockToken),
                0,
                100000 ether,
                34730,
                1000
            )
        );
        lockStakingProxy = new ERC1967Proxy(address(lockStaking), lockStakingData);
        lockStaking = LockStaking(address(lockStakingProxy));
        sigUtils = new LockSigUtils(lockStaking.getDomainSeparator());

        // Initalize signature for claim reward
        uint256 rewardAmount = 20 ether;
        string memory requestId = "lockStakingClaimOrder#1";
        LockSigUtils.ClaimRequest memory claimRequest =
            LockSigUtils.ClaimRequest({requestId: requestId, beneficiary: ACCOUNT_ONE, rewardAmount: rewardAmount});
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(VALIDATOR_PRIVATE_KEY, digest);
        bytes memory signature = getSignatureFromVRS(v, r, s);
        // Transfer LOCK token to contract for reward distribution
        lockToken.transfer(address(lockStaking), 100000 ether);
        // Using account one
        vm.startPrank(ACCOUNT_ONE);
        lockToken.approve(address(lockStaking), 2 * lockAmount);
        // Lock one Lock Token for 200 days
        lockStaking.addLockToken(lockAmount, 200 days);
        skip(1 days);
        lockStaking.addLockToken(lockAmount, 200 days);
        // Since the LOCK staking contract is not set, all next tx will be revert
        vm.expectRevert("LOCKON Vesting: Forbidden");
        lockStaking.claimPendingReward(requestId, rewardAmount, signature);
    }

    function test_cancel_claim_order() public {
        initializeAndConfig();
        uint256 stakeAmount = 10 ether;
        uint256 rewardAmount = 1 ether;
        string memory requestId = "lockStakingClaimOrder#1";
        LockSigUtils.ClaimRequest memory claimRequest =
            LockSigUtils.ClaimRequest({requestId: requestId, beneficiary: ACCOUNT_ONE, rewardAmount: rewardAmount});
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(VALIDATOR_PRIVATE_KEY, digest);

        bytes memory signature = getSignatureFromVRS(v, r, s);
        // Using account one with generated signature
        vm.startPrank(ACCOUNT_ONE);
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
        initializeAndConfig();
        uint256 stakeAmount = 10 ether;
        uint256 rewardAmount = 1 ether;
        string memory requestId = "lockStakingClaimOrder#1";
        LockSigUtils.ClaimRequest memory claimRequest =
            LockSigUtils.ClaimRequest({requestId: requestId, beneficiary: ACCOUNT_ONE, rewardAmount: rewardAmount});
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(VALIDATOR_PRIVATE_KEY, digest);

        bytes memory signature = getSignatureFromVRS(v, r, s);
        // User not stake any Lock Token but still call to cancel claim
        vm.prank(ACCOUNT_ONE);
        vm.expectRevert("LOCK Staking: User hasn't staked any token yet");
        lockStaking.cancelClaimOrder(requestId, rewardAmount, signature);
        // Account two using signature that is generated for account one
        vm.startPrank(ACCOUNT_TWO);
        lockToken.approve(address(lockStaking), stakeAmount);
        lockStaking.addLockToken(stakeAmount, 100 days);
        vm.expectRevert("LOCK Staking: Invalid signature");
        lockStaking.cancelClaimOrder(requestId, rewardAmount, signature);
        // Reward that already claimed cannot be cancelled
        vm.startPrank(ACCOUNT_ONE);
        lockToken.approve(address(lockStaking), stakeAmount);
        lockStaking.addLockToken(stakeAmount, 100 days);
        lockStaking.claimPendingReward(requestId, rewardAmount, signature);
        vm.expectRevert("LOCK Staking: Request already processed");
        lockStaking.cancelClaimOrder(requestId, rewardAmount, signature);
    }

    function test_pause_and_unpause() public {
        initializeAndConfig();
        vm.prank(OWNER);
        lockStaking.pause();
        // Cannot do any action when contract is paused
        vm.startPrank(ACCOUNT_ONE);
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
            LockSigUtils.ClaimRequest({requestId: requestId, beneficiary: ACCOUNT_ONE, rewardAmount: rewardAmount});
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(VALIDATOR_PRIVATE_KEY, digest);
        bytes memory signature = getSignatureFromVRS(v, r, s);
        vm.expectRevert(EnforcedPause.selector);
        lockStaking.claimPendingReward(requestId, rewardAmount, signature);
        vm.stopPrank();
        // Transaction can be executed normal when unpause
        vm.prank(OWNER);
        lockStaking.unPause();
        vm.startPrank(ACCOUNT_ONE);
        lockToken.approve(address(lockStaking), amount);
        lockStaking.addLockToken(amount, 100 days);
        (uint256 lockedAmount,, uint256 lockDuration,,,,) = lockStaking.userInfo(ACCOUNT_ONE);
        assertEq(lockedAmount, amount);
        assertEq(lockDuration, 100 days);
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
        initializeAndConfig();
        uint256 rewardAmount = 10 ether;
        string memory requestId = "lockStakingClaimOrder#1";
        LockSigUtils.ClaimRequest memory claimRequest =
            LockSigUtils.ClaimRequest({requestId: requestId, beneficiary: ACCOUNT_ONE, rewardAmount: rewardAmount});
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(VALIDATOR_PRIVATE_KEY, digest);

        bytes memory signature = getSignatureFromVRS(v, r, s);
        // Using account one with generated signature
        vm.startPrank(ACCOUNT_ONE);
        lockToken.approve(address(lockStaking), lockAmount);
        lockStaking.addLockToken(lockAmount, 100 days);
        skip(100 days);
        address signer = lockStaking.getSignerForRequest(requestId, ACCOUNT_ONE, rewardAmount, signature);
        assertEq(signer, validator);
    }
}
