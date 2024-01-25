// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IndexStaking} from "../contracts/IndexStaking.sol";
import {LockToken} from "../contracts/LockToken.sol";
import {LockonVesting} from "../contracts/LockonVesting.sol";
import {IndexSigUtils} from "./IndexSigUtil.sol";

contract MockERC20Token is ERC20 {
    address public constant accountOne = address(1);
    address public constant accountTwo = address(2);
    address public constant accountThree = address(3);
    uint256 public constant testAccountInitialBalance = 1000 ether;

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        _mint(msg.sender, 1_000_000 ether);
        _mint(accountOne, testAccountInitialBalance);
        _mint(accountTwo, testAccountInitialBalance);
        _mint(accountThree, testAccountInitialBalance * 1000);
    }
}

contract IndexStakingTest is Test {
    IndexStaking public indexStaking;
    LockonVesting public lockonVesting;
    LockToken public lockToken;
    MockERC20Token lpiToken;
    MockERC20Token lbiToken;
    MockERC20Token fakeToken;
    IndexSigUtils internal sigUtils;

    uint256 validatorPrivateKey = 123;
    address public constant owner = address(bytes20(bytes("owner")));
    address public constant accountOne = address(1);
    address public constant accountTwo = address(2);
    address public constant accountThree = address(3);
    address public validator = vm.addr(validatorPrivateKey);
    uint256 public constant testAccountInitialBalance = 1000 ether;
    uint256 public constant cumulativePendingReward = 1 ether;

    error OwnableUnauthorizedAccount(address account);

    error EnforcedPause();

    function setUp() public {
        vm.startPrank(owner);
        lockToken = new LockToken();
        lockToken.initialize("LockToken", "LOCK", owner, validator);
        lockonVesting = new LockonVesting();
        lockonVesting.initialize(owner, address(lockToken));
        indexStaking = new IndexStaking();
        deal(owner, 100 ether);
        // Create 2 mock token
        lpiToken = new MockERC20Token("LOCKON Passive Index", "LPI");
        lbiToken = new MockERC20Token("LOCKON Balance Index", "LBI");
        fakeToken = new MockERC20Token("Fake Token", "FAKE");
    }

    function initilizeAndConfig() public {
        lockonVesting.addAddressDepositPermission(address(indexStaking));
        IndexStaking.InitPoolInfo memory firstPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(address(lpiToken)), 2300, block.timestamp);
        IndexStaking.InitPoolInfo memory secondPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(address(lbiToken)), 2300, block.timestamp);
        IndexStaking.InitPoolInfo[] memory poolInfos = new IndexStaking.InitPoolInfo[](2);
        poolInfos[0] = firstPoolInfo;
        poolInfos[1] = secondPoolInfo;
        indexStaking.initialize(
            owner, validator, address(lockonVesting), address(lockToken), 100000 ether, "INDEX_STAKING", "1", poolInfos
        );
        sigUtils = new IndexSigUtils(indexStaking.getDomainSeparator());
        // NOTICE: In real life, token will be transfer to contract from BE wallet for reward distribution
        // Transfer reward to contract for token distribute
        lockToken.transfer(address(indexStaking), 100000 ether);
        vm.stopPrank();
    }

    function getSignatureFromVRS(uint8 v, bytes32 r, bytes32 s) internal pure returns (bytes memory) {
        // v ++ (length(r) + 0x80 ) ++ r ++ (length(s) + 0x80) ++ s
        // v ++ r ++ s
        return abi.encodePacked(r, s, v);
    }

    function test_initialize_fail() public {
        lockonVesting.addAddressDepositPermission(address(indexStaking));
        IndexStaking.InitPoolInfo memory firstPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(address(0)), 2300, block.timestamp);
        IndexStaking.InitPoolInfo[] memory poolInfos = new IndexStaking.InitPoolInfo[](2);
        poolInfos[0] = firstPoolInfo;
        vm.expectRevert("Index Staking: Zero address not allowed");
        indexStaking.initialize(
            owner, validator, address(lockonVesting), address(lockToken), 100000 ether, "INDEX_STAKING", "1", poolInfos
        );
        poolInfos[0] = IndexStaking.InitPoolInfo(IERC20(address(accountThree)), 0, block.timestamp);
        poolInfos[1] = IndexStaking.InitPoolInfo(IERC20(address(accountTwo)), 2300, block.timestamp);
        vm.expectRevert("Index Staking: Pool bonus rate per second must be greater than 0");
        indexStaking.initialize(
            owner, validator, address(lockonVesting), address(lockToken), 100000 ether, "INDEX_STAKING", "1", poolInfos
        );
    }

    function test_add_new_pool() public {
        initilizeAndConfig();
        // Create new token and add new pool
        vm.startPrank(owner);
        MockERC20Token erc20Token = new MockERC20Token("ERC20 Token", "ERC20");
        vm.recordLogs();
        indexStaking.addStakingPool(address(erc20Token), 2300, block.timestamp);
        assertEq(indexStaking.currentNumOfPools(), 3);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("PoolAdded(address,uint256,uint256,uint256)"));
        (address token,) = abi.decode(entries[0].data, (address, uint256));
        assertEq(address(token), address(erc20Token));
    }

    function test_add_pool_fail() public {
        initilizeAndConfig();
        // Check for owner role
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, accountOne));
        vm.prank(accountOne);
        indexStaking.addStakingPool(address(lbiToken), 2300, block.timestamp);
        // Zero address is forbidden
        vm.expectRevert("Index Staking: Zero address not allowed");
        vm.prank(owner);
        indexStaking.addStakingPool(address(0), 2300, block.timestamp);
        // Pool bonus rate per second must larger than 0
        vm.expectRevert("Index Staking: Pool bonus rate per second must be greater than 0");
        vm.prank(owner);
        indexStaking.addStakingPool(address(accountThree), 0, block.timestamp);
        // Pool already exist
        vm.expectRevert("Index Staking: Pool already exist");
        vm.prank(owner);
        indexStaking.addStakingPool(address(lbiToken), 2300, block.timestamp);
    }

    function test_deposit() public {
        initilizeAndConfig();
        // Using account one
        vm.startPrank(accountOne);
        uint256 depositAmount = 1 ether;
        uint256 currentRewardAmount = indexStaking.currentRewardAmount();
        // Deposit one LPI token to according pool for staking
        vm.recordLogs();
        lpiToken.approve(address(indexStaking), depositAmount);
        indexStaking.deposit(address(lpiToken), depositAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 accountOneBalanceAfterDeposit = testAccountInitialBalance - depositAmount;
        assertEq(lpiToken.balanceOf(accountOne), accountOneBalanceAfterDeposit);
        assertEq(lpiToken.balanceOf(address(indexStaking)), depositAmount);
        // Get account one data after deposit
        (, uint256 totalStakedAmount, uint256 rewardPerToken, uint256 bonusRatePerSecond, uint256 lastRewardTimestamp,)
        = indexStaking.tokenPoolInfo(address(lpiToken));
        assertEq(rewardPerToken, 0);
        assertEq(totalStakedAmount, depositAmount);
        assertEq(lastRewardTimestamp, block.timestamp);
        (uint256 stakedAmount, uint256 lastStakedTimestamp, uint256 rewardDebt,) =
            indexStaking.userInfo(accountOne, address(lpiToken));
        assertEq(stakedAmount, depositAmount);
        assertEq(lastStakedTimestamp, block.timestamp);
        assertEq(rewardDebt, 0);
        // Check for emitted event
        assertEq(
            entries[2].topics[0],
            keccak256("DepositSucceeded(address,address,uint256,uint256,uint256,uint256,uint256,uint256)")
        );
        // Still using account one, deposit to other pool (LBI Pool)
        lbiToken.approve(address(indexStaking), depositAmount);
        indexStaking.deposit(address(lbiToken), depositAmount);
        assertEq(lbiToken.balanceOf(accountOne), accountOneBalanceAfterDeposit);
        assertEq(lbiToken.balanceOf(address(indexStaking)), depositAmount);
        (, totalStakedAmount, rewardPerToken,, lastRewardTimestamp,) = indexStaking.tokenPoolInfo(address(lbiToken));
        assertEq(rewardPerToken, 0);
        assertEq(totalStakedAmount, depositAmount);
        assertEq(lastRewardTimestamp, block.timestamp);
        (stakedAmount, lastStakedTimestamp, rewardDebt,) = indexStaking.userInfo(accountOne, address(lbiToken));
        assertEq(stakedAmount, depositAmount);
        assertEq(lastStakedTimestamp, block.timestamp);
        assertEq(rewardDebt, 0);
        // Deposit into the same LBI pool and check for data
        skip(1);
        lbiToken.approve(address(indexStaking), depositAmount);
        indexStaking.deposit(address(lbiToken), depositAmount);
        assertEq(lbiToken.balanceOf(accountOne), accountOneBalanceAfterDeposit - depositAmount);
        assertEq(lbiToken.balanceOf(address(indexStaking)), depositAmount * 2);

        (, totalStakedAmount, rewardPerToken,, lastRewardTimestamp,) = indexStaking.tokenPoolInfo(address(lbiToken));
        assertEq(rewardPerToken, currentRewardAmount * bonusRatePerSecond / 2 / depositAmount);
        assertEq(totalStakedAmount, depositAmount * 2);
        assertEq(lastRewardTimestamp, block.timestamp);
        (stakedAmount, lastStakedTimestamp, rewardDebt,) = indexStaking.userInfo(accountOne, address(lbiToken));
        assertEq(stakedAmount, depositAmount * 2);
        assertEq(lastStakedTimestamp, block.timestamp);
        assertEq(rewardDebt, depositAmount * 2 * rewardPerToken / indexStaking.PRECISION());
        // Using account two to deposit into LPI pool, skip data check
        vm.stopPrank();
        vm.startPrank(accountTwo);
        lpiToken.approve(address(indexStaking), depositAmount);
        indexStaking.deposit(address(lpiToken), depositAmount);
    }

    function test_deposit_fail() public {
        initilizeAndConfig();
        // Create new token and add new pool with latency staking start time
        vm.startPrank(owner);
        MockERC20Token erc20Token = new MockERC20Token("ERC20 Token", "ERC20");
        indexStaking.addStakingPool(address(erc20Token), 2300, block.timestamp + 1 minutes);
        vm.stopPrank();
        // Using account one
        vm.startPrank(accountOne);
        uint256 depositAmount = 1 ether;
        // Staking not start
        vm.expectRevert("Index Staking: Staking not start");
        indexStaking.deposit(address(erc20Token), depositAmount);
        // Increase 1 minute
        skip(60);
        // Deposit with deposit amount = 0
        vm.expectRevert("Index Staking: Stake amount must be greater than 0");
        indexStaking.deposit(address(lpiToken), 0);
        // Pool not exist
        vm.expectRevert("Index Staking: Pool not exist");
        indexStaking.deposit(address(fakeToken), depositAmount);
    }

    function test_withdraw() public {
        initilizeAndConfig();
        // Using account one
        vm.startPrank(accountOne);
        uint256 depositAmount = 1 ether;
        // Deposit 1 token into pool
        lpiToken.approve(address(indexStaking), depositAmount);
        indexStaking.deposit(address(lpiToken), depositAmount);
        (, uint256 totalStakedAmount, uint256 rewardPerToken, uint256 bonusRatePerSecond, uint256 lastRewardTimestamp,)
        = indexStaking.tokenPoolInfo(address(lpiToken));
        assertEq(rewardPerToken, 0);
        assertEq(totalStakedAmount, depositAmount);
        assertEq(lastRewardTimestamp, block.timestamp);
        (uint256 stakedAmount, uint256 lastStakedTimestamp, uint256 rewardDebt,) =
            indexStaking.userInfo(accountOne, address(lpiToken));
        assertEq(stakedAmount, depositAmount);
        assertEq(lastStakedTimestamp, block.timestamp);
        assertEq(rewardDebt, 0);
        uint256 accountOneBalanceBefore = lpiToken.balanceOf(accountOne);
        uint256 currentRewardAmount = indexStaking.currentRewardAmount();
        // Withdraw 30% of the staked
        uint256 withdrawAmount = (depositAmount * 3) / 10;
        vm.recordLogs();
        skip(1);
        indexStaking.withdraw(address(lpiToken), withdrawAmount);
        (, totalStakedAmount, rewardPerToken,, lastRewardTimestamp,) = indexStaking.tokenPoolInfo(address(lpiToken));
        uint256 firstRewardPerToken = currentRewardAmount * bonusRatePerSecond / 2 / depositAmount;
        assertEq(rewardPerToken, firstRewardPerToken);
        assertEq(lastRewardTimestamp, block.timestamp);
        (stakedAmount, lastStakedTimestamp, rewardDebt,) = indexStaking.userInfo(accountOne, address(lpiToken));
        assertEq(stakedAmount, depositAmount * 7 / 10);
        assertEq(rewardDebt, rewardPerToken * stakedAmount / indexStaking.PRECISION());
        skip(10 days);
        currentRewardAmount = indexStaking.currentRewardAmount();
        indexStaking.withdraw(address(lpiToken), withdrawAmount);
        (, totalStakedAmount, rewardPerToken,, lastRewardTimestamp,) = indexStaking.tokenPoolInfo(address(lpiToken));
        assertEq(
            rewardPerToken,
            (10 days) * currentRewardAmount * bonusRatePerSecond / 2 * 10 / (depositAmount * 7) + firstRewardPerToken
        );
        assertEq(totalStakedAmount, depositAmount * 4 / 10);
        (stakedAmount, lastStakedTimestamp, rewardDebt,) = indexStaking.userInfo(accountOne, address(lpiToken));
        assertEq(stakedAmount, depositAmount * 4 / 10);
        assertEq(lastStakedTimestamp, 1);
        assertEq(rewardDebt, stakedAmount * rewardPerToken / indexStaking.PRECISION());
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 accountOneBalanceAfter = lpiToken.balanceOf(accountOne);
        assertEq(accountOneBalanceAfter, accountOneBalanceBefore + withdrawAmount * 2);
        // Check for emitted event
        assertEq(
            entries[2].topics[0],
            keccak256("WithdrawSucceeded(address,address,uint256,uint256,uint256,uint256,uint256)")
        );
    }

    function test_withdraw_fail() public {
        initilizeAndConfig();
        // Using account one
        vm.startPrank(accountOne);
        uint256 depositAmount = 1 ether;
        // Deposit 1 token into pool
        lpiToken.approve(address(indexStaking), depositAmount);
        indexStaking.deposit(address(lpiToken), depositAmount);
        // Pool do not exist
        vm.expectRevert("Index Staking: Pool do not exist");
        indexStaking.withdraw(address(fakeToken), depositAmount + 1);
        // User withdraw more than staked amount
        vm.expectRevert("Index Staking: Withdrawal amount exceed stake amount");
        indexStaking.withdraw(address(lpiToken), depositAmount + 1);
        // Or withdraw in the another pool that user hasn't staked any
        vm.expectRevert("Index Staking: Withdrawal amount exceed stake amount");
        indexStaking.withdraw(address(lbiToken), depositAmount);
    }

    // This is only the testing of signature verification on the contract, the actual staking amount would be calculated off-chain
    function test_claim_index_staking_reward() public {
        initilizeAndConfig();
        uint256 stakeAmount = 10 ether;
        uint256 claimAmount = 1 ether;
        string memory requestId = "indexStakingClaimOrder#1";
        IndexSigUtils.ClaimRequest memory claimRequest = IndexSigUtils.ClaimRequest({
            requestId: requestId,
            beneficiary: accountOne,
            stakeToken: address(lpiToken),
            cumulativePendingReward: cumulativePendingReward,
            claimAmount: claimAmount
        });
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPrivateKey, digest);
        bytes memory signature = getSignatureFromVRS(v, r, s);
        // Using account one with generated signature from validator address to claim staking reward
        vm.startPrank(accountOne);
        lpiToken.approve(address(indexStaking), stakeAmount * 2);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        uint256 userRewardDebt = getUserRewardDebt(indexStaking, accountOne, address(lpiToken));
        skip(10 days);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        uint256 accountContractVestingBefore = lockToken.balanceOf(address(lockonVesting));
        assertEq(
            getUserCumulativePendingReward(indexStaking, accountOne, address(lpiToken)),
            calculateCumulatePendingReward(
                stakeAmount,
                getRewardPerTokenOfPool(indexStaking, address(lpiToken)),
                indexStaking.PRECISION(),
                userRewardDebt
            )
        );
        uint256 cumulativePendingRewardBeforeClaim =
            getUserCumulativePendingReward(indexStaking, accountOne, address(lpiToken));
        vm.recordLogs();
        indexStaking.claimIndexStakingReward(
            requestId, address(lpiToken), cumulativePendingReward, claimAmount, signature
        );
        assertEq(
            getUserCumulativePendingReward(indexStaking, accountOne, address(lpiToken)),
            cumulativePendingRewardBeforeClaim - cumulativePendingReward
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // Transfer token to vesting contract
        assertEq(lockToken.balanceOf(address(lockonVesting)), accountContractVestingBefore + claimAmount);
        assertEq(
            entries[4].topics[0], keccak256("IndexStakingRewardClaimed(address,string,address,uint256,uint256,uint256)")
        );
    }

    function test_claim_index_staking_reward_fail() public {
        initilizeAndConfig();
        uint256 stakeAmount = 10 ether;
        uint256 claimAmount = 1 ether;
        uint256 invalidAmount = 100001 ether;
        string memory requestId = "indexStakingClaimOrder#1";

        // With valid amount
        IndexSigUtils.ClaimRequest memory validClaimRequest = IndexSigUtils.ClaimRequest({
            requestId: requestId,
            beneficiary: accountOne,
            stakeToken: address(lpiToken),
            cumulativePendingReward: cumulativePendingReward,
            claimAmount: claimAmount
        });
        bytes32 digest = sigUtils.getTypedDataHash(validClaimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPrivateKey, digest);

        bytes memory signatureWithValidAmount = getSignatureFromVRS(v, r, s);

        //with invalid amount
        IndexSigUtils.ClaimRequest memory invalidCancelClaimRequest = IndexSigUtils.ClaimRequest({
            requestId: requestId,
            beneficiary: accountOne,
            stakeToken: address(lpiToken),
            cumulativePendingReward: cumulativePendingReward,
            claimAmount: invalidAmount
        });
        digest = sigUtils.getTypedDataHash(invalidCancelClaimRequest);
        (v, r, s) = vm.sign(validatorPrivateKey, digest);

        bytes memory signatureWithInvalidAmount = getSignatureFromVRS(v, r, s);
        // User not stake any Token but still call to withdraw
        vm.prank(accountOne);
        vm.expectRevert("Index Staking: User hasn't staked any token yet");
        indexStaking.claimIndexStakingReward(
            requestId, address(lpiToken), cumulativePendingReward, claimAmount, signatureWithValidAmount
        );
        // Account two using signature that is generated for account one
        vm.startPrank(accountTwo);
        lpiToken.approve(address(indexStaking), stakeAmount);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        vm.expectRevert("Index Staking: Invalid signature");
        indexStaking.claimIndexStakingReward(
            requestId, address(lpiToken), cumulativePendingReward, claimAmount, signatureWithValidAmount
        );
        // Claim the wrong pool
        vm.startPrank(accountOne);
        lbiToken.approve(address(indexStaking), stakeAmount);
        indexStaking.deposit(address(lbiToken), stakeAmount);
        vm.expectRevert("Index Staking: Invalid signature");
        indexStaking.claimIndexStakingReward(
            requestId, address(lbiToken), cumulativePendingReward, claimAmount, signatureWithValidAmount
        );

        lpiToken.approve(address(indexStaking), stakeAmount * 2);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        skip(10 days);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        // Claim exceed maximum reward amount
        vm.expectRevert("Index Staking: Claim amount exceed remaining reward");
        indexStaking.claimIndexStakingReward(
            requestId, address(lpiToken), cumulativePendingReward, invalidAmount, signatureWithInvalidAmount
        );
        // Prevent double claim
        indexStaking.claimIndexStakingReward(
            requestId, address(lpiToken), cumulativePendingReward, claimAmount, signatureWithValidAmount
        );
        vm.expectRevert("Index Staking: Request already processed");
        indexStaking.claimIndexStakingReward(
            requestId, address(lpiToken), cumulativePendingReward, claimAmount, signatureWithValidAmount
        );
    }

    function test_cancel_claim_order() public {
        initilizeAndConfig();
        uint256 stakeAmount = 10 ether;
        uint256 claimAmount = 1 ether;
        string memory requestId = "indexStakingClaimOrder#1";
        IndexSigUtils.ClaimRequest memory claimRequest = IndexSigUtils.ClaimRequest({
            requestId: requestId,
            beneficiary: accountOne,
            stakeToken: address(lpiToken),
            cumulativePendingReward: cumulativePendingReward,
            claimAmount: claimAmount
        });
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPrivateKey, digest);

        bytes memory signature = getSignatureFromVRS(v, r, s);
        // Using account one with generated signature
        vm.startPrank(accountOne);
        lpiToken.approve(address(indexStaking), stakeAmount);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        vm.recordLogs();
        indexStaking.cancelClaimOrder(requestId, address(lpiToken), cumulativePendingReward, claimAmount, signature);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("ClaimOrderCancel(address,string,address)"));
        // Make sure that the requestId cannot be claimed after cancel
        vm.expectRevert("Index Staking: Request already processed");
        indexStaking.claimIndexStakingReward(
            requestId, address(lpiToken), cumulativePendingReward, claimAmount, signature
        );
    }

    function test_cancel_claim_order_fail() public {
        initilizeAndConfig();
        uint256 stakeAmount = 10 ether;
        uint256 claimAmount = 1 ether;
        string memory requestId = "indexStakingClaimOrder#1";
        IndexSigUtils.ClaimRequest memory claimRequest = IndexSigUtils.ClaimRequest({
            requestId: requestId,
            beneficiary: accountOne,
            stakeToken: address(lpiToken),
            cumulativePendingReward: cumulativePendingReward,
            claimAmount: claimAmount
        });
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPrivateKey, digest);

        bytes memory signature = getSignatureFromVRS(v, r, s);
        // User not stake any Lock Token but still call to cancel claim
        vm.prank(accountOne);
        vm.expectRevert("Index Staking: User hasn't staked any token yet");
        indexStaking.cancelClaimOrder(requestId, address(lpiToken), cumulativePendingReward, claimAmount, signature);
        // Account two using signature that is generated for account one
        vm.startPrank(accountTwo);
        lpiToken.approve(address(indexStaking), stakeAmount * 2);
        indexStaking.deposit(address(lpiToken), stakeAmount * 2);
        vm.expectRevert("Index Staking: Invalid signature");
        indexStaking.cancelClaimOrder(requestId, address(lpiToken), cumulativePendingReward, claimAmount, signature);
        // Reward that already claimed cannot be cancelled
        vm.startPrank(accountOne);
        lpiToken.approve(address(indexStaking), stakeAmount * 2);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        skip(10 days);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        indexStaking.claimIndexStakingReward(
            requestId, address(lpiToken), cumulativePendingReward, claimAmount, signature
        );
        vm.expectRevert("Index Staking: Request already processed");
        indexStaking.cancelClaimOrder(requestId, address(lpiToken), cumulativePendingReward, claimAmount, signature);
    }

    function test__add_address_update_permission() public {
        initilizeAndConfig();
        vm.startPrank(owner);
        vm.recordLogs();
        indexStaking.addPermissionedAddress(accountOne);
        assertEq(indexStaking.isAllowedUpdate(accountOne), true);
        address[] memory listAllowedUpdate = indexStaking.getListAllowedUpdate();
        assertEq(listAllowedUpdate[0], accountOne);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("PermissionedAddressUpdated(address,bool,uint256)"));
    }

    function test__remove_address_update_permission() public {
        initilizeAndConfig();
        vm.startPrank(owner);
        vm.recordLogs();
        indexStaking.addPermissionedAddress(accountOne);
        indexStaking.removePermissionedAddress(accountOne);
        indexStaking.addPermissionedAddress(accountOne);
        assertEq(indexStaking.isAllowedUpdate(accountOne), true);
        address[] memory listAllowedUpdate = indexStaking.getListAllowedUpdate();
        assertEq(listAllowedUpdate[0], accountOne);
        indexStaking.removePermissionedAddress(accountOne);
        listAllowedUpdate = indexStaking.getListAllowedUpdate();
        assertEq(indexStaking.isAllowedUpdate(accountOne), false);
        assertEq(listAllowedUpdate.length, 0);
        indexStaking.addPermissionedAddress(accountOne);
        indexStaking.addPermissionedAddress(accountTwo);
        indexStaking.removePermissionedAddress(accountTwo);
        listAllowedUpdate = indexStaking.getListAllowedUpdate();
        assertEq(listAllowedUpdate[0], accountOne);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("PermissionedAddressUpdated(address,bool,uint256)"));
        assertEq(entries[1].topics[0], keccak256("PermissionedAddressUpdated(address,bool,uint256)"));
        assertEq(entries[2].topics[0], keccak256("PermissionedAddressUpdated(address,bool,uint256)"));
        assertEq(entries[3].topics[0], keccak256("PermissionedAddressUpdated(address,bool,uint256)"));
    }

    function test__add_and_remove_address_update_permission_fail() public {
        initilizeAndConfig();
        vm.startPrank(owner);
        indexStaking.addPermissionedAddress(accountOne);
        vm.expectRevert("Index Staking: Zero address not allowed");
        indexStaking.addPermissionedAddress(address(0));
        vm.expectRevert("Index Staking: List allowed address already contains this address");
        indexStaking.addPermissionedAddress(accountOne);
        vm.expectRevert("Index Staking: Zero address not allowed");
        indexStaking.removePermissionedAddress(address(0));
        vm.expectRevert("Index Staking: List allowed address does not contain this address");
        indexStaking.removePermissionedAddress(accountTwo);
    }

    function test_update_current_reward_amount() public {
        initilizeAndConfig();
        vm.startPrank(owner);
        indexStaking.addPermissionedAddress(accountOne);
        vm.recordLogs();
        indexStaking.updateCurrentRewardAmount(10 ether);
        assertEq(indexStaking.currentRewardAmount(), 99990 ether);
        vm.stopPrank();
        vm.startPrank(accountOne);
        indexStaking.updateCurrentRewardAmount(100 ether);
        assertEq(indexStaking.currentRewardAmount(), 99890 ether);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("CurrentRewardAmountUpdated(address,uint256,uint256)"));
        assertEq(entries[1].topics[0], keccak256("CurrentRewardAmountUpdated(address,uint256,uint256)"));
    }

    function test_update_current_reward_amount_fail() public {
        initilizeAndConfig();
        vm.startPrank(accountOne);
        vm.expectRevert("Index Staking: Forbidden");
        indexStaking.updateCurrentRewardAmount(919999);
        vm.stopPrank();
        vm.startPrank(owner);
        vm.expectRevert("Index Staking: Reduction amount must be larger than 0");
        indexStaking.updateCurrentRewardAmount(0);
    }

    function test_set_validator_address() public {
        initilizeAndConfig();
        vm.prank(owner);
        vm.recordLogs();
        indexStaking.setValidatorAddress(accountOne);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(indexStaking.validatorAddress(), accountOne);
        assertEq(entries[0].topics[0], keccak256("ValidatorAddressUpdated(address,uint256)"));
    }

    function test_set_validator_address_fail() public {
        initilizeAndConfig();
        vm.prank(accountOne);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, accountOne));
        indexStaking.setValidatorAddress(accountOne);
        vm.expectRevert("Index Staking: Zero address not allowed");
        vm.prank(owner);
        indexStaking.setValidatorAddress(address(0));
    }

    function test_set_lockon_vesting_address() public {
        initilizeAndConfig();
        vm.prank(owner);
        vm.recordLogs();
        indexStaking.setLockonVesting(accountOne);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(indexStaking.lockonVesting(), accountOne);
        assertEq(entries[0].topics[0], keccak256("LockonVestingAddressUpdated(address,uint256)"));
    }

    function test_set_lockon_vesting_address_fail() public {
        initilizeAndConfig();
        vm.startPrank(accountOne);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, accountOne));
        indexStaking.setLockonVesting(accountOne);
        vm.stopPrank();
        vm.expectRevert("Index Staking: Zero address not allowed");
        vm.startPrank(owner);
        indexStaking.setLockonVesting(address(0));
    }

    function test_set_bonus_rate_per_second() public {
        initilizeAndConfig();
        vm.startPrank(owner);
        vm.recordLogs();
        indexStaking.setBonusRatePerSecond(address(lbiToken), 2500);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        (,,, uint256 bonusRatePerSecond,,) = indexStaking.tokenPoolInfo(address(lbiToken));
        assertEq(bonusRatePerSecond, 2500);
        assertEq(
            entries[0].topics[0],
            keccak256("BonusRatePerSecondUpdated(address,uint256,uint256,uint256,uint256,uint256)")
        );
    }

    function test_set_bonus_rate_per_second_fail() public {
        initilizeAndConfig();
        vm.startPrank(accountOne);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, accountOne));
        indexStaking.setBonusRatePerSecond(address(lbiToken), 2400);
        vm.stopPrank();
        vm.startPrank(owner);
        MockERC20Token erc20Token = new MockERC20Token("ERC20 Token", "ERC20");
        indexStaking.addStakingPool(address(erc20Token), 2300, block.timestamp + 1 minutes);
        // Pool not exist
        vm.expectRevert("Index Staking: Pool do not exist");
        indexStaking.setBonusRatePerSecond(address(fakeToken), 2990);
        vm.expectRevert("Index Staking: Bonus rate per second must be greater than 0");
        indexStaking.setBonusRatePerSecond(address(erc20Token), 0);
    }

    function test_view_function() public {
        initilizeAndConfig();
        vm.startPrank(owner);
        assertEq(
            indexStaking.rewardTokenPerSecond(address(lpiToken)), 100000 ether * 2300 / 2 / indexStaking.PRECISION()
        );
        assertEq(
            indexStaking.getRewardMultiplier(address(lpiToken), 100, 1000),
            (1000 - 100) * indexStaking.rewardTokenPerSecond(address(lpiToken))
        );
        assertEq(
            indexStaking.getRewardMultiplier(address(lpiToken), 1, 100000 days), indexStaking.currentRewardAmount()
        );
    }

    function test__update_pool() public {
        lockonVesting.addAddressDepositPermission(address(indexStaking));
        IndexStaking.InitPoolInfo memory firstPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(address(lpiToken)), 2300, block.timestamp);
        IndexStaking.InitPoolInfo memory secondPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(address(lbiToken)), 2300, block.timestamp);
        IndexStaking.InitPoolInfo[] memory poolInfos = new IndexStaking.InitPoolInfo[](2);
        poolInfos[0] = firstPoolInfo;
        poolInfos[1] = secondPoolInfo;
        indexStaking.initialize(
            owner, validator, address(lockonVesting), address(lockToken), 100000 ether, "INDEX_STAKING", "1", poolInfos
        );
        uint256 depositAmount = 1 ether;

        lbiToken.transfer(address(indexStaking), depositAmount * 2);
        lbiToken.transfer(address(accountOne), depositAmount * 2);
        lockToken.transfer(address(indexStaking), 1000 ether);
        lockToken.approve(address(indexStaking), depositAmount * 2);

        vm.stopPrank();
        vm.startPrank(accountOne);
        lbiToken.approve(address(indexStaking), depositAmount * 2);
        uint256 currentRewardAmount = indexStaking.currentRewardAmount();

        // user first deposit
        indexStaking.deposit(address(lbiToken), depositAmount);
        skip(10 days);
        (, uint256 totalStakedAmount, uint256 rewardPerToken, uint256 bonusRatePerSecond, uint256 lastRewardTimestamp,)
        = indexStaking.tokenPoolInfo(address(lbiToken));
        currentRewardAmount = indexStaking.currentRewardAmount();
        indexStaking.updatePool(address(lbiToken));
        indexStaking.deposit(address(lbiToken), depositAmount);
        (,, rewardPerToken,, lastRewardTimestamp,) = indexStaking.tokenPoolInfo(address(lbiToken));
        assertEq(rewardPerToken, 10 days * currentRewardAmount * bonusRatePerSecond / 2 / totalStakedAmount);
        assertEq(lastRewardTimestamp, 10 days + 1);
    }

    function test__update_pool_failed() public {
        lockonVesting.addAddressDepositPermission(address(indexStaking));
        IndexStaking.InitPoolInfo memory firstPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(address(lpiToken)), 2300, block.timestamp);
        IndexStaking.InitPoolInfo memory secondPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(address(lbiToken)), 2300000000, block.timestamp);
        IndexStaking.InitPoolInfo[] memory poolInfos = new IndexStaking.InitPoolInfo[](2);
        poolInfos[0] = firstPoolInfo;
        poolInfos[1] = secondPoolInfo;
        indexStaking.initialize(
            owner, validator, address(lockonVesting), address(lockToken), 1000 ether, "INDEX_STAKING", "1", poolInfos
        );
        uint256 depositAmount = 10000 ether;

        lbiToken.transfer(address(indexStaking), depositAmount * 2);
        lbiToken.transfer(address(accountOne), depositAmount * 2);
        lpiToken.transfer(address(indexStaking), depositAmount * 2);
        lpiToken.transfer(address(accountOne), depositAmount * 2);
        lockToken.transfer(address(indexStaking), 10 ether);
        lockToken.approve(address(indexStaking), depositAmount * 2);

        vm.stopPrank();
        vm.startPrank(accountOne);
        lbiToken.approve(address(indexStaking), depositAmount * 2);
        lpiToken.approve(address(indexStaking), depositAmount * 2);
        // user first deposit pool lbi
        indexStaking.deposit(address(lbiToken), depositAmount);
        skip(900 days);
        vm.expectRevert("Index Staking: Stake token reward distributed exceed supply");
        indexStaking.deposit(address(lbiToken), depositAmount);
    }

    function test__get_current_reward_per_token() public {
        lockonVesting.addAddressDepositPermission(address(indexStaking));
        IndexStaking.InitPoolInfo memory firstPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(address(lpiToken)), 2300, block.timestamp);
        IndexStaking.InitPoolInfo memory secondPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(address(lbiToken)), 2300, block.timestamp);
        IndexStaking.InitPoolInfo[] memory poolInfos = new IndexStaking.InitPoolInfo[](2);
        poolInfos[0] = firstPoolInfo;
        poolInfos[1] = secondPoolInfo;
        indexStaking.initialize(
            owner,
            validator,
            address(lockonVesting),
            address(lockToken),
            2000000000 ether,
            "INDEX_STAKING",
            "1",
            poolInfos
        );
        uint256 depositAmount = 10 ether;

        lbiToken.transfer(address(indexStaking), depositAmount * 2);
        lbiToken.transfer(address(accountOne), depositAmount * 2);
        lockToken.transfer(address(indexStaking), 1000 ether);
        lockToken.approve(address(indexStaking), depositAmount * 2);

        vm.stopPrank();
        vm.startPrank(accountOne);
        lbiToken.approve(address(indexStaking), depositAmount * 2);
        uint256 currentRewardAmount = indexStaking.currentRewardAmount();

        // user first deposit
        indexStaking.deposit(address(lbiToken), depositAmount);
        indexStaking.getCurrentRewardPerToken(address(lbiToken));
        (, uint256 totalStakedAmount, uint256 rewardPerToken, uint256 bonusRatePerSecond, uint256 lastRewardTimestamp,)
        = indexStaking.tokenPoolInfo(address(lbiToken));
        uint256 oldTotalStakedAmount = totalStakedAmount;
        skip(117);
        assertEq(
            indexStaking.getCurrentRewardPerToken(address(lbiToken)),
            117 * currentRewardAmount * bonusRatePerSecond / 2 / totalStakedAmount
        );
        // Update current reward amount
        currentRewardAmount = indexStaking.currentRewardAmount();
        indexStaking.deposit(address(lbiToken), depositAmount);
        (,, rewardPerToken,, lastRewardTimestamp,) = indexStaking.tokenPoolInfo(address(lbiToken));

        assertEq(lastRewardTimestamp, 118);
        indexStaking.withdraw(address(lbiToken), depositAmount * 2);
        (, totalStakedAmount, rewardPerToken,, lastRewardTimestamp,) = indexStaking.tokenPoolInfo(address(lbiToken));
        // Reward per token unchanged
        assertEq(rewardPerToken, 117 * currentRewardAmount * bonusRatePerSecond / 2 / oldTotalStakedAmount);
        assertEq(indexStaking.getCurrentRewardPerToken(address(lbiToken)), rewardPerToken);
        assertEq(totalStakedAmount, 0);
    }

    function test__get_current_reward_per_token_failed() public {
        lockonVesting.addAddressDepositPermission(address(indexStaking));
        IndexStaking.InitPoolInfo memory firstPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(address(lpiToken)), 2300, block.timestamp);
        IndexStaking.InitPoolInfo memory secondPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(address(lbiToken)), 2300000000000, block.timestamp);
        IndexStaking.InitPoolInfo[] memory poolInfos = new IndexStaking.InitPoolInfo[](2);
        poolInfos[0] = firstPoolInfo;
        poolInfos[1] = secondPoolInfo;
        indexStaking.initialize(
            owner, validator, address(lockonVesting), address(lockToken), 1000 ether, "INDEX_STAKING", "1", poolInfos
        );
        uint256 depositAmount = 10000 ether;

        lbiToken.transfer(address(indexStaking), depositAmount * 2);
        lbiToken.transfer(address(accountOne), depositAmount * 2);
        lpiToken.transfer(address(indexStaking), depositAmount * 2);
        lpiToken.transfer(address(accountOne), depositAmount * 2);
        lockToken.transfer(address(indexStaking), 10 ether);
        lockToken.approve(address(indexStaking), depositAmount * 2);

        vm.stopPrank();
        vm.startPrank(accountOne);
        lbiToken.approve(address(indexStaking), depositAmount * 2);
        lpiToken.approve(address(indexStaking), depositAmount * 2);
        // user first deposit pool lbi
        indexStaking.deposit(address(lbiToken), depositAmount);
        skip(900 days);
        vm.expectRevert("Index Staking: Stake token reward distributed exceed supply");
        indexStaking.deposit(address(lbiToken), depositAmount);
        indexStaking.getCurrentRewardPerToken(address(lbiToken));
    }

    function test_allocate_token() public {
        initilizeAndConfig();
        uint256 lockAmount = 1 ether;
        uint256 oldLockBalance = lockToken.balanceOf(address(indexStaking));
        // Using account one
        vm.startPrank(owner);
        vm.recordLogs();
        // Allocate amount of LOCK token
        lockToken.approve(address(indexStaking), lockAmount);
        indexStaking.allocateLockToken(lockAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[2].topics[0], keccak256("LockTokenAllocated(address,uint256)"));
        assertEq(lockToken.balanceOf(address(indexStaking)), oldLockBalance + lockAmount);
    }

    function test_deallocate_token() public {
        initilizeAndConfig();
        uint256 lockAmount = 1 ether;
        uint256 oldLockBalance = lockToken.balanceOf(address(indexStaking));
        // Using account one
        vm.startPrank(owner);
        vm.recordLogs();
        // Dellocate amount of LOCK token
        lockToken.approve(address(indexStaking), lockAmount);
        indexStaking.deallocateLockToken(lockAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[2].topics[0], keccak256("LockTokenDeallocated(address,uint256)"));
        assertEq(lockToken.balanceOf(address(indexStaking)), oldLockBalance - lockAmount);
    }

    function test_pause_and_unpause() public {
        initilizeAndConfig();
        vm.prank(owner);
        indexStaking.pause();
        // Cannot do any action when contract is paused
        vm.startPrank(accountOne);
        uint256 amount = 1 ether;
        vm.expectRevert(EnforcedPause.selector);
        indexStaking.deposit(address(lbiToken), amount);
        vm.expectRevert(EnforcedPause.selector);
        indexStaking.withdraw(address(lbiToken), amount);
        vm.expectRevert(EnforcedPause.selector);
        indexStaking.claimIndexStakingReward(
            "requestId", address(lbiToken), cumulativePendingReward, amount, bytes("0x")
        );
        vm.stopPrank();
        // Transaction can be executed normal when unpause
        vm.prank(owner);
        indexStaking.unPause();
        vm.startPrank(accountOne);
        lpiToken.approve(address(indexStaking), amount);
        indexStaking.deposit(address(lpiToken), amount);
    }

    function test_get_signer_for_request() public {
        initilizeAndConfig();
        uint256 claimAmount = 1 ether;
        string memory requestId = "indexStakingClaimOrder#1";
        IndexSigUtils.ClaimRequest memory claimRequest = IndexSigUtils.ClaimRequest({
            requestId: requestId,
            beneficiary: accountOne,
            stakeToken: address(lpiToken),
            cumulativePendingReward: cumulativePendingReward,
            claimAmount: claimAmount
        });
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPrivateKey, digest);

        bytes memory signature = getSignatureFromVRS(v, r, s);
        // Using account one with generated signature
        vm.startPrank(accountOne);
        lpiToken.approve(address(indexStaking), claimAmount);
        indexStaking.deposit(address(lpiToken), claimAmount);
        address signer = indexStaking.getSignerForRequest(
            requestId, accountOne, address(lpiToken), cumulativePendingReward, claimAmount, signature
        );
        assertEq(signer, validator);
    }

    function getRewardPerTokenOfPool(IndexStaking indexStakingContract, address tokenAddress)
        public
        view
        returns (uint256)
    {
        (,, uint256 rewardPerToken,,,) = indexStakingContract.tokenPoolInfo(tokenAddress);
        return rewardPerToken;
    }

    function getUserCumulativePendingReward(IndexStaking indexStakingContract, address user, address tokenAddress)
        public
        view
        returns (uint256)
    {
        (,,, uint256 userCumulativePendingReward) = indexStakingContract.userInfo(user, tokenAddress);
        return userCumulativePendingReward;
    }

    function getUserStakedAmount(IndexStaking indexStakingContract, address user, address tokenAddress)
        public
        view
        returns (uint256)
    {
        (uint256 stakedAmount,,,) = indexStakingContract.userInfo(user, tokenAddress);
        return stakedAmount;
    }

    function getUserRewardDebt(IndexStaking indexStakingContract, address user, address tokenAddress)
        public
        view
        returns (uint256)
    {
        (,, uint256 rewardDebt,) = indexStakingContract.userInfo(user, tokenAddress);
        return rewardDebt;
    }

    function calculateCumulatePendingReward(
        uint256 stakedAmount,
        uint256 rewardPerToken,
        uint256 precision,
        uint256 rewardDebt
    ) public pure returns (uint256) {
        return ((stakedAmount * rewardPerToken) / precision) - rewardDebt;
    }
}
