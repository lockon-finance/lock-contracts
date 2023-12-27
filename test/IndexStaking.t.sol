// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IndexStaking} from "../contracts/IndexStaking.sol";
import {LockToken} from "../contracts/LockToken.sol";
import {LockonVesting} from "../contracts/LockonVesting.sol";
import {SigUtils} from "./SigUtil.sol";

contract MockERC20Token is ERC20 {
    address public constant accountOne = address(1);
    address public constant accountTwo = address(2);
    uint256 public constant testAccountInitialBalance = 1000 ether;

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        _mint(msg.sender, 1_000_000 ether);
        _mint(accountOne, testAccountInitialBalance);
        _mint(accountTwo, testAccountInitialBalance);
    }
}

contract IndexStakingTest is Test {
    IndexStaking public indexStaking;
    LockonVesting public lockonVesting;
    LockToken public lockToken;
    MockERC20Token lpiToken;
    MockERC20Token lbiToken;
    MockERC20Token fakeToken;
    SigUtils internal sigUtils;

    struct PoolInfo {
        IERC20 stakeToken;
        uint256 totalStaked;
        uint256 startTimestamp;
        uint256 lastStakedTimestamp;
    }

    uint256 validatorPrivateKey = 123;
    address public constant owner = address(bytes20(bytes("owner")));
    address public constant accountOne = address(1);
    address public constant accountTwo = address(2);
    address public validator = vm.addr(validatorPrivateKey);
    uint256 public constant testAccountInitialBalance = 1000 ether;

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
        lpiToken = new MockERC20Token("Lockon Passive Index", "LPI");
        lbiToken = new MockERC20Token("Lockon Balance Index", "LBI");
        fakeToken = new MockERC20Token("Fake Token", "FAKE");
    }

    function initilizeAndConfig() public {
        lockonVesting.setIndexStakingContract(address(indexStaking));
        IndexStaking.PoolInfo memory firstPoolInfo =
            IndexStaking.PoolInfo(IERC20(address(lpiToken)), 0, block.timestamp);
        IndexStaking.PoolInfo memory secondPoolInfo =
            IndexStaking.PoolInfo(IERC20(address(lbiToken)), 0, block.timestamp);
        IndexStaking.PoolInfo[] memory poolInfos = new IndexStaking.PoolInfo[](2);
        poolInfos[0] = firstPoolInfo;
        poolInfos[1] = secondPoolInfo;
        indexStaking.initialize(
            owner, validator, address(lockonVesting), address(lockToken), 100000 ether, "INDEX_STAKING", "1", poolInfos
        );
        sigUtils = new SigUtils(indexStaking.getDomainSeparator());
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

    function test_initialize_fail_with_pool_zero_address() public {
        lockonVesting.setIndexStakingContract(address(indexStaking));
        IndexStaking.PoolInfo memory firstPoolInfo = IndexStaking.PoolInfo(IERC20(address(0)), 0, block.timestamp);
        IndexStaking.PoolInfo[] memory poolInfos = new IndexStaking.PoolInfo[](2);
        poolInfos[0] = firstPoolInfo;
        vm.expectRevert("Index Staking: Zero address not allowed");
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
        indexStaking.addStakingPool(address(erc20Token), block.timestamp);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("PoolAdded(address,uint256)"));
        (address token,) = abi.decode(entries[0].data, (address, uint256));
        assertEq(address(token), address(erc20Token));
    }

    function test_add_pool_fail() public {
        initilizeAndConfig();
        // Check for owner role
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, accountOne));
        vm.prank(accountOne);
        indexStaking.addStakingPool(address(lbiToken), block.timestamp);
        // Zero address is forbidden
        vm.expectRevert("Index Staking: Zero address not allowed");
        vm.prank(owner);
        indexStaking.addStakingPool(address(0), block.timestamp);
        // Pool already exist
        vm.expectRevert("Index Staking: Pool already exist");
        vm.prank(owner);
        indexStaking.addStakingPool(address(lbiToken), block.timestamp);
    }

    function test_deposit() public {
        initilizeAndConfig();
        // Using account one
        vm.startPrank(accountOne);
        uint256 depositAmount = 1 ether;
        // Deposit one LPI token to according pool for staking
        vm.recordLogs();
        lpiToken.approve(address(indexStaking), depositAmount);
        indexStaking.deposit(address(lpiToken), depositAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 accountOneBalanceAfterDeposit = testAccountInitialBalance - depositAmount;
        assertEq(lpiToken.balanceOf(accountOne), accountOneBalanceAfterDeposit);
        assertEq(lpiToken.balanceOf(address(indexStaking)), depositAmount);
        // Get account one data after deposit
        (uint256 stakedAmount,, uint256 lastStakedTimestamp) = indexStaking.userInfo(accountOne, address(lpiToken));
        assertEq(stakedAmount, depositAmount);
        assertEq(lastStakedTimestamp, block.timestamp);
        // Check for emitted event
        assertEq(entries[2].topics[0], keccak256("DepositSucceeded(address,address,uint256)"));
        // Still using account one, deposit to other pool (LBI Pool)
        lbiToken.approve(address(indexStaking), depositAmount);
        indexStaking.deposit(address(lbiToken), depositAmount);
        assertEq(lbiToken.balanceOf(accountOne), accountOneBalanceAfterDeposit);
        assertEq(lbiToken.balanceOf(address(indexStaking)), depositAmount);
        // Deposit into the same LBI pool and check for data
        lbiToken.approve(address(indexStaking), depositAmount);
        indexStaking.deposit(address(lbiToken), depositAmount);
        assertEq(lbiToken.balanceOf(accountOne), accountOneBalanceAfterDeposit - depositAmount);
        assertEq(lbiToken.balanceOf(address(indexStaking)), depositAmount * 2);
        (stakedAmount,, lastStakedTimestamp) = indexStaking.userInfo(accountOne, address(lbiToken));
        assertEq(stakedAmount, depositAmount * 2);
        assertEq(lastStakedTimestamp, block.timestamp);
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
        indexStaking.addStakingPool(address(erc20Token), block.timestamp + 1 minutes);
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
        uint256 accountOneBalanceBefore = lpiToken.balanceOf(accountOne);
        // Withdraw 30% of the staked first
        uint256 withdrawAmount = (depositAmount * 3) / 10;
        vm.recordLogs();
        indexStaking.withdraw(address(lpiToken), withdrawAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 accountOneBalanceAfter = lpiToken.balanceOf(accountOne);
        assertEq(accountOneBalanceAfter, accountOneBalanceBefore + withdrawAmount);
        // Check for emitted event
        assertEq(entries[1].topics[0], keccak256("WithdrawSucceeded(address,address,uint256)"));
        // Withdraw the rest of the staked token
        indexStaking.withdraw(address(lpiToken), depositAmount - withdrawAmount);
        assertEq(lpiToken.balanceOf(accountOne), accountOneBalanceAfter + depositAmount - withdrawAmount);
    }

    function test_withdraw_fail() public {
        initilizeAndConfig();
        // Using account one
        vm.startPrank(accountOne);
        uint256 depositAmount = 1 ether;
        // Deposit 1 token into pool
        lpiToken.approve(address(indexStaking), depositAmount);
        indexStaking.deposit(address(lpiToken), depositAmount);
        // User withdraw more than staked amount
        vm.expectRevert("Index Staking: Withdrawal amount exceed stake amount");
        indexStaking.withdraw(address(lpiToken), depositAmount + 1);
        // Or withdraw in the another pool that user hasn't staked any
        vm.expectRevert("Index Staking: Withdrawal amount exceed stake amount");
        indexStaking.withdraw(address(lbiToken), depositAmount);
    }

    // // This is only the testing of signature verification on the contract, the actual staking amount would be calculated off-chain
    function test_claim_lock_staking_reward() public {
        initilizeAndConfig();
        uint256 stakeAmount = 10 ether;
        uint256 claimAmount = 1 ether;
        string memory requestId = "indexStakingClaimOrder#1";
        SigUtils.ClaimRequest memory claimRequest = SigUtils.ClaimRequest({
            requestId: requestId,
            beneficiary: accountOne,
            stakeToken: address(lpiToken),
            claimAmount: claimAmount
        });
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPrivateKey, digest);
        bytes memory signature = getSignatureFromVRS(v, r, s);
        // Using account one with generated signature from validator address to claim staking reward
        vm.startPrank(accountOne);
        lpiToken.approve(address(indexStaking), stakeAmount);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        uint256 accountContractVestingBefore = lockToken.balanceOf(address(lockonVesting));
        vm.recordLogs();
        indexStaking.claimIndexStakingReward(requestId, address(lpiToken), claimAmount, signature);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // Provide the case that no pool for staking lock token and no one send lock token to this contract
        assertEq(indexStaking.currentRewardAmount(), lockToken.balanceOf(address(indexStaking)));
        // Transfer token to vesting contract
        assertEq(lockToken.balanceOf(address(lockonVesting)), accountContractVestingBefore + claimAmount);
        assertEq(entries[2].topics[0], keccak256("IndexStakingRewardClaimed(address,string,address,uint256)"));
    }

    function test_claim_index_staking_reward_fail() public {
        initilizeAndConfig();
        uint256 stakeAmount = 10 ether;
        uint256 claimAmount = 1 ether;
        uint256 invalidAmount = 100001 ether;
        string memory requestId = "indexStakingClaimOrder#1";

        //with valid amount
        SigUtils.ClaimRequest memory validClaimRequest = SigUtils.ClaimRequest({
            requestId: requestId,
            beneficiary: accountOne,
            stakeToken: address(lpiToken),
            claimAmount: claimAmount
        });
        bytes32 digest = sigUtils.getTypedDataHash(validClaimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPrivateKey, digest);

        bytes memory signatureWithValidAmount = getSignatureFromVRS(v, r, s);

        //with invalid amount
        SigUtils.ClaimRequest memory invalidCancelClaimRequest = SigUtils.ClaimRequest({
            requestId: requestId,
            beneficiary: accountOne,
            stakeToken: address(lpiToken),
            claimAmount: invalidAmount
        });
        digest = sigUtils.getTypedDataHash(invalidCancelClaimRequest);
        (v, r, s) = vm.sign(validatorPrivateKey, digest);

        bytes memory signatureWithInvalidAmount = getSignatureFromVRS(v, r, s);
        // User not stake any Token but still call to withdraw
        vm.prank(accountOne);
        vm.expectRevert("Index Staking: User hasn't staked any token yet");
        indexStaking.claimIndexStakingReward(requestId, address(lpiToken), claimAmount, signatureWithValidAmount);
        // Account two using signature that is generated for account one
        vm.startPrank(accountTwo);
        lpiToken.approve(address(indexStaking), stakeAmount);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        vm.expectRevert("Index Staking: Invalid signature");
        indexStaking.claimIndexStakingReward(requestId, address(lpiToken), claimAmount, signatureWithValidAmount);
        // Claim the wrong pool
        vm.startPrank(accountOne);
        lbiToken.approve(address(indexStaking), stakeAmount);
        indexStaking.deposit(address(lbiToken), stakeAmount);
        vm.expectRevert("Index Staking: Invalid signature");
        indexStaking.claimIndexStakingReward(requestId, address(lbiToken), claimAmount, signatureWithValidAmount);

        lpiToken.approve(address(indexStaking), stakeAmount);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        // Claim exceed maximum reward amount
        vm.expectRevert("Index Staking: Claim amount exceed remaining reward");
        indexStaking.claimIndexStakingReward(requestId, address(lpiToken), invalidAmount, signatureWithInvalidAmount);
        // Prevent double claim
        indexStaking.claimIndexStakingReward(requestId, address(lpiToken), claimAmount, signatureWithValidAmount);
        vm.expectRevert("Index Staking: Request already processed");
        indexStaking.claimIndexStakingReward(requestId, address(lpiToken), claimAmount, signatureWithValidAmount);
    }

    function test_cancel_claim_order() public {
        initilizeAndConfig();
        uint256 stakeAmount = 10 ether;
        uint256 claimAmount = 1 ether;
        string memory requestId = "indexStakingClaimOrder#1";
        SigUtils.ClaimRequest memory claimRequest = SigUtils.ClaimRequest({
            requestId: requestId,
            beneficiary: accountOne,
            stakeToken: address(lpiToken),
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
        indexStaking.cancelClaimOrder(requestId, address(lpiToken), claimAmount, signature);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("ClaimOrderCancel(address,string,address)"));
        // Make sure that the requestId cannot be claimed after cancel
        vm.expectRevert("Index Staking: Request already processed");
        indexStaking.claimIndexStakingReward(requestId, address(lpiToken), claimAmount, signature);
    }

    function test_cancel_claim_order_fail() public {
        initilizeAndConfig();
        uint256 stakeAmount = 10 ether;
        uint256 claimAmount = 1 ether;
        string memory requestId = "indexStakingClaimOrder#1";
        SigUtils.ClaimRequest memory claimRequest = SigUtils.ClaimRequest({
            requestId: requestId,
            beneficiary: accountOne,
            stakeToken: address(lpiToken),
            claimAmount: claimAmount
        });
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPrivateKey, digest);

        bytes memory signature = getSignatureFromVRS(v, r, s);
        // User not stake any Lock Token but still call to cancel claim
        vm.prank(accountOne);
        vm.expectRevert("Index Staking: User hasn't staked any token yet");
        indexStaking.cancelClaimOrder(requestId, address(lpiToken), claimAmount, signature);
        // Account two using signature that is generated for account one
        vm.startPrank(accountTwo);
        lpiToken.approve(address(indexStaking), stakeAmount);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        vm.expectRevert("Index Staking: Invalid signature");
        indexStaking.cancelClaimOrder(requestId, address(lpiToken), claimAmount, signature);
        // Reward that already claimed cannot be cancelled
        vm.startPrank(accountOne);
        lpiToken.approve(address(indexStaking), stakeAmount);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        indexStaking.claimIndexStakingReward(requestId, address(lpiToken), claimAmount, signature);
        vm.expectRevert("Index Staking: Request already processed");
        indexStaking.cancelClaimOrder(requestId, address(lpiToken), claimAmount, signature);
    }

    function test_set_validator_address() public {
        initilizeAndConfig();
        vm.prank(owner);
        indexStaking.setValidatorAddress(accountOne);
        assertEq(indexStaking.validatorAddress(), accountOne);
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
        indexStaking.setLockonVesting(accountOne);
        assertEq(indexStaking.lockonVesting(), accountOne);
    }

    function test_set_lockon_vesting_address_fail() public {
        initilizeAndConfig();
        vm.prank(accountOne);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, accountOne));
        indexStaking.setLockonVesting(accountOne);
        vm.expectRevert("Index Staking: Zero address not allowed");
        vm.prank(owner);
        indexStaking.setLockonVesting(address(0));
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
        indexStaking.claimIndexStakingReward("requestId", address(lbiToken), amount, bytes("0x"));
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
        uint256 stakeAmount = 10 ether;
        uint256 claimAmount = 1 ether;
        string memory requestId = "indexStakingClaimOrder#1";
        SigUtils.ClaimRequest memory claimRequest = SigUtils.ClaimRequest({
            requestId: requestId,
            beneficiary: accountOne,
            stakeToken: address(lpiToken),
            claimAmount: claimAmount
        });
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPrivateKey, digest);

        bytes memory signature = getSignatureFromVRS(v, r, s);
        // Using account one with generated signature
        vm.startPrank(accountOne);
        lpiToken.approve(address(indexStaking), stakeAmount);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        address signer =
            indexStaking.getSignerForRequest(requestId, accountOne, address(lpiToken), claimAmount, signature);
        assertEq(signer, validator);
    }
}
