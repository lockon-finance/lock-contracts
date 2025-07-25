// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IndexStaking} from "../contracts/IndexStaking.sol";
import {LockToken} from "../contracts/LockToken.sol";
import {LockonVesting} from "../contracts/LockonVesting.sol";
import {IndexSigUtils} from "./IndexSigUtil.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockERC20Token is ERC20 {
    address public constant ACCOUNT_ONE = address(1);
    address public constant ACCOUNT_TWO = address(2);
    address public constant ACCOUNT_THREE = address(3);
    uint256 public constant TEST_ACCOUNT_INITIAL_BALANCE = 1000 ether;

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        _mint(msg.sender, 1_000_000 ether);
        _mint(ACCOUNT_ONE, TEST_ACCOUNT_INITIAL_BALANCE);
        _mint(ACCOUNT_TWO, TEST_ACCOUNT_INITIAL_BALANCE);
        _mint(ACCOUNT_THREE, TEST_ACCOUNT_INITIAL_BALANCE * 1000);
    }
}

contract IndexStakingTest is Test {
    IndexStaking public indexStaking;
    LockonVesting public lockonVesting;
    LockToken public lockToken;
    ERC1967Proxy tokenProxy;
    ERC1967Proxy lockonVestingProxy;
    ERC1967Proxy indexStakingProxy;
    MockERC20Token lpiToken;
    MockERC20Token lbiToken;
    MockERC20Token fakeToken;
    IndexSigUtils internal sigUtils;

    uint256 public constant VALIDATOR_PRIVATE_KEY = 123;
    address public constant OWNER = address(bytes20(bytes("OWNER")));
    address public constant ACCOUNT_ONE = address(1);
    address public constant ACCOUNT_TWO = address(2);
    address public constant ACCOUNT_THREE = address(3);
    address public validator = vm.addr(VALIDATOR_PRIVATE_KEY);
    uint256 public constant TEST_ACCOUNT_INITIAL_BALANCE = 1000 ether;
    uint256 private constant PRECISION = 1e12;

    error OwnableUnauthorizedAccount(address account);

    error EnforcedPause();

    function setUp() public {
        vm.startPrank(OWNER);
        bytes memory tokenData = abi.encodeCall(lockToken.initialize, ("LockToken", "LOCK", OWNER, validator));
        lockToken = new LockToken();
        tokenProxy = new ERC1967Proxy(address(lockToken), tokenData);
        lockToken = LockToken(address(tokenProxy));
        lockonVesting = new LockonVesting();
        uint256[] memory vestingCategoryIds = new uint256[](2);
        vestingCategoryIds[0] = 3;
        vestingCategoryIds[1] = 4;
        uint256[] memory vestingPeriods = new uint256[](2);
        vestingPeriods[0] = 300 days;
        vestingPeriods[1] = 300 days;
        bytes memory lockonVestingData = abi.encodeCall(lockonVesting.initialize, (OWNER, address(lockToken),vestingCategoryIds, vestingPeriods));
        lockonVestingProxy = new ERC1967Proxy(address(lockonVesting), lockonVestingData);
        lockonVesting = LockonVesting(address(lockonVestingProxy));
        indexStaking = new IndexStaking();
        deal(OWNER, 100 ether);
        // Create 2 mock token
        lpiToken = new MockERC20Token("LOCKON Passive Index", "LPI");
        lbiToken = new MockERC20Token("LOCKON Balance Index", "LBI");
        fakeToken = new MockERC20Token("Fake Token", "FAKE");
    }

    function initializeAndConfig() public {
        IndexStaking.InitPoolInfo memory firstPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(address(lpiToken)), 2300, block.timestamp, 3);
        IndexStaking.InitPoolInfo memory secondPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(address(lbiToken)), 2300, block.timestamp, 4);
        IndexStaking.InitPoolInfo[] memory poolInfos = new IndexStaking.InitPoolInfo[](2);
        poolInfos[0] = firstPoolInfo;
        poolInfos[1] = secondPoolInfo;
        bytes memory indexStakingData = abi.encodeCall(
            indexStaking.initialize,
            (
                OWNER,
                validator,
                address(lockonVesting),
                address(lockToken),
                100000 ether,
                "INDEX_STAKING",
                "1",
                poolInfos
            )
        );
        indexStakingProxy = new ERC1967Proxy(address(indexStaking), indexStakingData);
        indexStaking = IndexStaking(address(indexStakingProxy));
        lockonVesting.addAddressDepositPermission(address(indexStaking));
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

    function getClaimSignature(
        string memory requestId,
        address beneficiary,
        address stakeToken,
        uint256 claimAmount
    ) internal view returns (bytes memory) {
        IndexSigUtils.ClaimRequest memory claimRequest = IndexSigUtils.ClaimRequest({
            requestId: requestId,
            beneficiary: beneficiary,
            stakeToken: stakeToken,
            claimAmount: claimAmount
        });
        bytes32 digest = sigUtils.getTypedDataHash(claimRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(VALIDATOR_PRIVATE_KEY, digest);
        return getSignatureFromVRS(v, r, s);
    }

    function test_initialize_fail_zero_address() public {
        IndexStaking.InitPoolInfo memory firstPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(address(0)), 2300, block.timestamp, 3);
        IndexStaking.InitPoolInfo[] memory poolInfos = new IndexStaking.InitPoolInfo[](2);
        poolInfos[0] = firstPoolInfo;
        poolInfos[1] = IndexStaking.InitPoolInfo(IERC20(ACCOUNT_TWO), 2300, block.timestamp, 4);
        vm.expectRevert("Index Staking: Zero address not allowed");
        bytes memory indexStakingData = abi.encodeCall(
            indexStaking.initialize,
            (
                OWNER,
                validator,
                address(lockonVesting),
                address(lockToken),
                100000 ether,
                "INDEX_STAKING",
                "1",
                poolInfos
            )
        );
        indexStakingProxy = new ERC1967Proxy(address(indexStaking), indexStakingData);
        indexStaking = IndexStaking(address(indexStakingProxy));
    }

    function test_initialize_fail_owner_zero_address() public {
        IndexStaking.InitPoolInfo memory firstPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(ACCOUNT_ONE), 2300, block.timestamp, 3);
        IndexStaking.InitPoolInfo[] memory poolInfos = new IndexStaking.InitPoolInfo[](2);
        poolInfos[0] = firstPoolInfo;
        poolInfos[1] = IndexStaking.InitPoolInfo(IERC20(ACCOUNT_TWO), 2300, block.timestamp, 4);
        vm.expectRevert("Index Staking: owner is the zero address");
        bytes memory indexStakingData = abi.encodeCall(
            indexStaking.initialize,
            (
                address(0),
                validator,
                address(lockonVesting),
                address(lockToken),
                100000 ether,
                "INDEX_STAKING",
                "1",
                poolInfos
            )
        );
        indexStakingProxy = new ERC1967Proxy(address(indexStaking), indexStakingData);
        indexStaking = IndexStaking(address(indexStakingProxy));
    }

    function test_initialize_fail_validator_zero_address() public {
        IndexStaking.InitPoolInfo memory firstPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(ACCOUNT_ONE), 2300, block.timestamp, 3);
        IndexStaking.InitPoolInfo[] memory poolInfos = new IndexStaking.InitPoolInfo[](2);
        poolInfos[0] = firstPoolInfo;
        poolInfos[1] = IndexStaking.InitPoolInfo(IERC20(ACCOUNT_TWO), 2300, block.timestamp, 4);
        vm.expectRevert("Index Staking: validator is the zero address");
        bytes memory indexStakingData = abi.encodeCall(
            indexStaking.initialize,
            (
                OWNER,
                address(0),
                address(lockonVesting),
                address(lockToken),
                100000 ether,
                "INDEX_STAKING",
                "1",
                poolInfos
            )
        );
        indexStakingProxy = new ERC1967Proxy(address(indexStaking), indexStakingData);
        indexStaking = IndexStaking(address(indexStakingProxy));
    }

    function test_initialize_fail_lockon_vesting_zero_address() public {
        IndexStaking.InitPoolInfo memory firstPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(ACCOUNT_ONE), 2300, block.timestamp, 3);
        IndexStaking.InitPoolInfo[] memory poolInfos = new IndexStaking.InitPoolInfo[](2);
        poolInfos[0] = firstPoolInfo;
        poolInfos[1] = IndexStaking.InitPoolInfo(IERC20(ACCOUNT_TWO), 2300, block.timestamp, 4);
        vm.expectRevert("Index Staking: lockonVesting is the zero address");
        bytes memory indexStakingData = abi.encodeCall(
            indexStaking.initialize,
            (OWNER, validator, address(0), address(lockToken), 100000 ether, "INDEX_STAKING", "1", poolInfos)
        );
        indexStakingProxy = new ERC1967Proxy(address(indexStaking), indexStakingData);
        indexStaking = IndexStaking(address(indexStakingProxy));
    }

    function test_initialize_fail_lock_token_zero_address() public {
        IndexStaking.InitPoolInfo memory firstPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(ACCOUNT_ONE), 2300, block.timestamp, 3);
        IndexStaking.InitPoolInfo[] memory poolInfos = new IndexStaking.InitPoolInfo[](2);
        poolInfos[0] = firstPoolInfo;
        poolInfos[1] = IndexStaking.InitPoolInfo(IERC20(ACCOUNT_TWO), 2300, block.timestamp, 4);
        vm.expectRevert("Index Staking: lockToken is the zero address");
        bytes memory indexStakingData = abi.encodeCall(
            indexStaking.initialize,
            (OWNER, validator, address(lockonVesting), address(0), 100000 ether, "INDEX_STAKING", "1", poolInfos)
        );
        indexStakingProxy = new ERC1967Proxy(address(indexStaking), indexStakingData);
        indexStaking = IndexStaking(address(indexStakingProxy));
    }

    function test_initialize_fail_pool_bonus_rate() public {
        IndexStaking.InitPoolInfo[] memory poolInfos = new IndexStaking.InitPoolInfo[](2);
        poolInfos[0] = IndexStaking.InitPoolInfo(IERC20(ACCOUNT_THREE), 0, block.timestamp, 3);
        poolInfos[1] = IndexStaking.InitPoolInfo(IERC20(ACCOUNT_TWO), 2300, block.timestamp, 4);
        vm.expectRevert("Index Staking: Pool bonus rate per second must be greater than 0");
        bytes memory indexStakingData = abi.encodeCall(
            indexStaking.initialize,
            (
                OWNER,
                validator,
                address(lockonVesting),
                address(lockToken),
                100000 ether,
                "INDEX_STAKING",
                "1",
                poolInfos
            )
        );
        indexStakingProxy = new ERC1967Proxy(address(indexStaking), indexStakingData);
        indexStaking = IndexStaking(address(indexStakingProxy));
    }

    function test_initialize_fail_vesting_category_id() public {
        IndexStaking.InitPoolInfo[] memory poolInfos = new IndexStaking.InitPoolInfo[](2);
        poolInfos[0] = IndexStaking.InitPoolInfo(IERC20(ACCOUNT_THREE), 2200, block.timestamp, 0);
        poolInfos[1] = IndexStaking.InitPoolInfo(IERC20(ACCOUNT_TWO), 2300, block.timestamp, 4);
        vm.expectRevert("Index Staking: Vesting category id must be greater than 0");
        bytes memory indexStakingData = abi.encodeCall(
            indexStaking.initialize,
            (
                OWNER,
                validator,
                address(lockonVesting),
                address(lockToken),
                100000 ether,
                "INDEX_STAKING",
                "1",
                poolInfos
            )
        );
        indexStakingProxy = new ERC1967Proxy(address(indexStaking), indexStakingData);
        indexStaking = IndexStaking(address(indexStakingProxy));
    }

    function test_add_new_pool() public {
        initializeAndConfig();
        // Create new token and add new pool
        vm.startPrank(OWNER);
        MockERC20Token erc20Token = new MockERC20Token("ERC20 Token", "ERC20");
        vm.recordLogs();
        indexStaking.addStakingPool(address(erc20Token), 2300, block.timestamp, 5);
        assertEq(indexStaking.currentNumOfPools(), 3);
        assertEq(indexStaking.stakeTokenToVestingCategoryId(address(erc20Token)), 5);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("PoolAdded(address,address,uint256,uint256,uint256,uint256)"));
        (address token,) = abi.decode(entries[0].data, (address, uint256));
        assertEq(token, address(erc20Token));
        MockERC20Token newErc20Token = new MockERC20Token("ERC20 Tokenn", "ERC20");
        indexStaking.addStakingPool(address(newErc20Token), 2300, block.timestamp, 6);
        assertEq(indexStaking.currentNumOfPools(), 4);
        assertEq(indexStaking.stakeTokenToVestingCategoryId(address(newErc20Token)), 6);
    }

    function test_add_pool_fail() public {
        initializeAndConfig();
        // Check for OWNER role
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, ACCOUNT_ONE));
        vm.prank(ACCOUNT_ONE);
        indexStaking.addStakingPool(address(lbiToken), 2300, block.timestamp, 5);
        // Zero address is forbidden
        vm.expectRevert("Index Staking: Zero address not allowed");
        vm.prank(OWNER);
        indexStaking.addStakingPool(address(0), 2300, block.timestamp, 5);
        // Pool bonus rate per second must larger than 0
        vm.expectRevert("Index Staking: Pool bonus rate per second must be greater than 0");
        vm.prank(OWNER);
        indexStaking.addStakingPool(ACCOUNT_THREE, 0, block.timestamp, 5);
        // Pool already exist
        vm.expectRevert("Index Staking: Pool already exist");
        vm.prank(OWNER);
        indexStaking.addStakingPool(address(lbiToken), 2300, block.timestamp, 5);
        // Vesting category id must be greater than 0
        vm.expectRevert("Index Staking: Vesting category id must be greater than 0");
        vm.prank(OWNER);
        indexStaking.addStakingPool(address(ACCOUNT_THREE), 2300, block.timestamp, 0);
    }

    function test_deposit() public {
        initializeAndConfig();
        // Using account one
        vm.startPrank(ACCOUNT_ONE);
        uint256 depositAmount = 1 ether;
        // Deposit one LPI token to according pool for staking
        lpiToken.approve(address(indexStaking), depositAmount);
        indexStaking.deposit(address(lpiToken), depositAmount);
        uint256 accOneBalanceAfterDeposit = TEST_ACCOUNT_INITIAL_BALANCE - depositAmount;
        assertEq(lpiToken.balanceOf(ACCOUNT_ONE), accOneBalanceAfterDeposit);
        assertEq(lpiToken.balanceOf(address(indexStaking)), depositAmount);
        // Get account one data after deposit
        (, uint256 totalStakedAmount,,, uint256 lastRewardTimestamp,) = indexStaking.tokenPoolInfo(address(lpiToken));
        assertEq(totalStakedAmount, depositAmount);
        assertEq(lastRewardTimestamp, block.timestamp);
        (uint256 stakedAmount, uint256 lastStakedTimestamp) = indexStaking.userInfo(ACCOUNT_ONE, address(lpiToken));
        assertEq(stakedAmount, depositAmount);
        assertEq(lastStakedTimestamp, block.timestamp);
        // Still using account one, deposit to other pool (LBI Pool)
        lbiToken.approve(address(indexStaking), depositAmount);
        indexStaking.deposit(address(lbiToken), depositAmount);
        assertEq(lbiToken.balanceOf(ACCOUNT_ONE), accOneBalanceAfterDeposit);
        assertEq(lbiToken.balanceOf(address(indexStaking)), depositAmount);
        (, totalStakedAmount,,, lastRewardTimestamp,) = indexStaking.tokenPoolInfo(address(lbiToken));
        assertEq(totalStakedAmount, depositAmount);
        assertEq(lastRewardTimestamp, block.timestamp);
        (stakedAmount, lastStakedTimestamp) = indexStaking.userInfo(ACCOUNT_ONE, address(lbiToken));
        assertEq(stakedAmount, depositAmount);
        assertEq(lastStakedTimestamp, block.timestamp);
        // Deposit into the same LBI pool and check for data
        skip(1);
        vm.recordLogs();
        lbiToken.approve(address(indexStaking), depositAmount);
        indexStaking.deposit(address(lbiToken), depositAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(lbiToken.balanceOf(ACCOUNT_ONE), accOneBalanceAfterDeposit - depositAmount);
        assertEq(lbiToken.balanceOf(address(indexStaking)), depositAmount * 2);

        (, totalStakedAmount,,, lastRewardTimestamp,) = indexStaking.tokenPoolInfo(address(lbiToken));
        assertEq(totalStakedAmount, depositAmount * 2);
        assertEq(lastRewardTimestamp, block.timestamp);
        (stakedAmount, lastStakedTimestamp) = indexStaking.userInfo(ACCOUNT_ONE, address(lbiToken));
        assertEq(stakedAmount, depositAmount * 2);
        assertEq(lastStakedTimestamp, block.timestamp);
        // Check for emitted event
        assertEq(entries[1].topics[0], keccak256("PoolDataUpdated(address,address,uint256,uint256,uint256)"));
        assertEq(
            entries[3].topics[0], keccak256("DepositSucceeded(address,address,uint256,uint256,uint256,uint256,uint256)")
        );
        // Using account two to deposit into LPI pool, skip data check
        vm.stopPrank();
        vm.startPrank(ACCOUNT_TWO);
        lpiToken.approve(address(indexStaking), depositAmount);
        indexStaking.deposit(address(lpiToken), depositAmount);
    }

    function test_deposit_fail() public {
        initializeAndConfig();
        // Create new token and add new pool with latency staking start time
        vm.startPrank(OWNER);
        MockERC20Token erc20Token = new MockERC20Token("ERC20 Token", "ERC20");
        indexStaking.addStakingPool(address(erc20Token), 2300, block.timestamp + 1 minutes, 3);
        vm.stopPrank();
        // Using account one
        vm.startPrank(ACCOUNT_ONE);
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
        initializeAndConfig();
        // Using account one
        vm.startPrank(ACCOUNT_ONE);
        uint256 depositAmount = 1 ether;
        // Deposit 1 token into pool
        lpiToken.approve(address(indexStaking), depositAmount);
        indexStaking.deposit(address(lpiToken), depositAmount);
        (, uint256 totalStakedAmount,,, uint256 lastRewardTimestamp,) = indexStaking.tokenPoolInfo(address(lpiToken));
        assertEq(totalStakedAmount, depositAmount);
        assertEq(lastRewardTimestamp, block.timestamp);
        (uint256 stakedAmount, uint256 lastStakedTimestamp) = indexStaking.userInfo(ACCOUNT_ONE, address(lpiToken));
        assertEq(stakedAmount, depositAmount);
        assertEq(lastStakedTimestamp, block.timestamp);
        uint256 ACCOUNT_ONEBalanceBefore = lpiToken.balanceOf(ACCOUNT_ONE);
        uint256 currentRewardAmount = indexStaking.currentRewardAmount();
        // Withdraw 30% of the staked
        uint256 withdrawAmount = (depositAmount * 3) / 10;
        vm.recordLogs();
        skip(1);
        indexStaking.withdraw(address(lpiToken), withdrawAmount);
        (, totalStakedAmount,,, lastRewardTimestamp,) = indexStaking.tokenPoolInfo(address(lpiToken));
        assertEq(lastRewardTimestamp, block.timestamp);
        (stakedAmount, lastStakedTimestamp) = indexStaking.userInfo(ACCOUNT_ONE, address(lpiToken));
        assertEq(stakedAmount, depositAmount * 7 / 10);
        skip(10 days);
        currentRewardAmount = indexStaking.currentRewardAmount();
        indexStaking.withdraw(address(lpiToken), withdrawAmount);
        (, totalStakedAmount,,, lastRewardTimestamp,) = indexStaking.tokenPoolInfo(address(lpiToken));
        assertEq(totalStakedAmount, depositAmount * 4 / 10);
        (stakedAmount, lastStakedTimestamp) = indexStaking.userInfo(ACCOUNT_ONE, address(lpiToken));
        assertEq(stakedAmount, depositAmount * 4 / 10);
        assertEq(lastStakedTimestamp, 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 ACCOUNT_ONEBalanceAfter = lpiToken.balanceOf(ACCOUNT_ONE);
        assertEq(ACCOUNT_ONEBalanceAfter, ACCOUNT_ONEBalanceBefore + withdrawAmount * 2);
        // Check for emitted event
        assertEq(entries[0].topics[0], keccak256("PoolDataUpdated(address,address,uint256,uint256,uint256)"));
        assertEq(entries[2].topics[0], keccak256("WithdrawSucceeded(address,address,uint256,uint256,uint256,uint256)"));
    }

    function test_withdraw_fail() public {
        initializeAndConfig();
        // Using account one
        vm.startPrank(ACCOUNT_ONE);
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
        initializeAndConfig();
        uint256 stakeAmount = 10 ether;
        uint256 claimAmount = 1 ether;
        string memory requestId = "indexStakingClaimOrder#1";
        bytes memory signature = getClaimSignature(requestId, ACCOUNT_ONE, address(lpiToken), claimAmount);
        // Using account one with generated signature from VALIDATOR address to claim staking reward
        vm.startPrank(ACCOUNT_ONE);
        lpiToken.approve(address(indexStaking), stakeAmount * 2);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        skip(10 days);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        uint256 accountContractVestingBefore = lockToken.balanceOf(address(lockonVesting));
        skip(10);
        vm.recordLogs();
        indexStaking.claimIndexStakingReward(requestId, address(lpiToken), claimAmount, signature);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // Transfer token to vesting contract
        assertEq(lockToken.balanceOf(address(lockonVesting)), accountContractVestingBefore + claimAmount);
        assertEq(entries[0].topics[0], keccak256("PoolDataUpdated(address,address,uint256,uint256,uint256)"));
        assertEq(entries[4].topics[0], keccak256("IndexStakingRewardClaimed(address,string,address,uint256,uint256)"));
    }

    function test_claim_index_staking_reward_fail() public {
        initializeAndConfig();
        uint256 stakeAmount = 10 ether;
        uint256 claimAmount = 1 ether;
        string memory requestId = "indexStakingClaimOrder#1";
        bytes memory signatureWithValidAmount = getClaimSignature(requestId, ACCOUNT_ONE, address(lpiToken), claimAmount);
        // User not stake any Token but still call to withdraw
        vm.startPrank(ACCOUNT_ONE);
        vm.expectRevert("Index Staking: User hasn't staked any token yet");
        indexStaking.claimIndexStakingReward(requestId, address(lpiToken), claimAmount, signatureWithValidAmount);
        // Account two using signature that is generated for account one
        vm.startPrank(ACCOUNT_TWO);
        lpiToken.approve(address(indexStaking), stakeAmount);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        vm.expectRevert("Index Staking: Invalid signature");
        indexStaking.claimIndexStakingReward(requestId, address(lpiToken), claimAmount, signatureWithValidAmount);
        // Claim the wrong pool
        vm.startPrank(ACCOUNT_ONE);
        lbiToken.approve(address(indexStaking), stakeAmount);
        indexStaking.deposit(address(lbiToken), stakeAmount);
        vm.expectRevert("Index Staking: Invalid signature");
        indexStaking.claimIndexStakingReward(requestId, address(lbiToken), claimAmount, signatureWithValidAmount);
        vm.expectRevert("Index Staking: Pool do not exist");
        indexStaking.claimIndexStakingReward(requestId, address(0), claimAmount, signatureWithValidAmount);
        lpiToken.approve(address(indexStaking), stakeAmount * 2);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        skip(10 days);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        // Prevent double claim
        indexStaking.claimIndexStakingReward(requestId, address(lpiToken), claimAmount, signatureWithValidAmount);
        vm.expectRevert("Index Staking: Request already processed");
        indexStaking.claimIndexStakingReward(requestId, address(lpiToken), claimAmount, signatureWithValidAmount);
        // Test zero claim amount
        string memory zeroRequestId = "indexStakingClaimOrder#2";
        bytes memory zeroSignature = getClaimSignature(zeroRequestId, ACCOUNT_ONE, address(lpiToken), 0);
        vm.expectRevert("Index Staking: Nothing to claim");
        indexStaking.claimIndexStakingReward(zeroRequestId, address(lpiToken), 0, zeroSignature);
    }

    function test_cancel_claim_order() public {
        initializeAndConfig();
        uint256 stakeAmount = 10 ether;
        uint256 claimAmount = 1 ether;
        string memory requestId = "indexStakingClaimOrder#1";
        bytes memory signature = getClaimSignature(requestId, ACCOUNT_ONE, address(lpiToken), claimAmount);
        // Using account one with generated signature
        vm.startPrank(ACCOUNT_ONE);
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
        initializeAndConfig();
        uint256 stakeAmount = 10 ether;
        uint256 claimAmount = 1 ether;
        string memory requestId = "indexStakingClaimOrder#1";
        bytes memory signature = getClaimSignature(requestId, ACCOUNT_ONE, address(lpiToken), claimAmount);
        // User not stake any Lock Token but still call to cancel claim
        vm.startPrank(ACCOUNT_ONE);
        vm.expectRevert("Index Staking: User hasn't staked any token yet");
        indexStaking.cancelClaimOrder(requestId, address(lpiToken), claimAmount, signature);
        // Account two using signature that is generated for account one
        vm.startPrank(ACCOUNT_TWO);
        lpiToken.approve(address(indexStaking), stakeAmount * 2);
        indexStaking.deposit(address(lpiToken), stakeAmount * 2);
        vm.expectRevert("Index Staking: Invalid signature");
        indexStaking.cancelClaimOrder(requestId, address(lpiToken), claimAmount, signature);
        // Reward that already claimed cannot be cancelled
        vm.startPrank(ACCOUNT_ONE);
        lpiToken.approve(address(indexStaking), stakeAmount * 2);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        skip(10 days);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        indexStaking.claimIndexStakingReward(requestId, address(lpiToken), claimAmount, signature);
        vm.expectRevert("Index Staking: Request already processed");
        indexStaking.cancelClaimOrder(requestId, address(lpiToken), claimAmount, signature);
    }

    function test_set_validator_address() public {
        initializeAndConfig();
        vm.prank(OWNER);
        vm.recordLogs();
        indexStaking.setValidatorAddress(ACCOUNT_ONE);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(indexStaking.validatorAddress(), ACCOUNT_ONE);
        assertEq(entries[0].topics[0], keccak256("ValidatorAddressUpdated(address,address,uint256)"));
    }

    function test_set_validator_address_fail() public {
        initializeAndConfig();
        vm.prank(ACCOUNT_ONE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, ACCOUNT_ONE));
        indexStaking.setValidatorAddress(ACCOUNT_ONE);
        vm.expectRevert("Index Staking: Zero address not allowed");
        vm.prank(OWNER);
        indexStaking.setValidatorAddress(address(0));
    }

    function test_set_lockon_vesting_address() public {
        initializeAndConfig();
        vm.prank(OWNER);
        vm.recordLogs();
        indexStaking.setLockonVesting(ACCOUNT_ONE);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(indexStaking.lockonVesting(), ACCOUNT_ONE);
        assertEq(entries[0].topics[0], keccak256("LockonVestingAddressUpdated(address,address,uint256)"));
    }

    function test_set_lockon_vesting_address_fail() public {
        initializeAndConfig();
        vm.startPrank(ACCOUNT_ONE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, ACCOUNT_ONE));
        indexStaking.setLockonVesting(ACCOUNT_ONE);
        vm.stopPrank();
        vm.expectRevert("Index Staking: Zero address not allowed");
        vm.startPrank(OWNER);
        indexStaking.setLockonVesting(address(0));
    }

    function test_set_bonus_rate_per_second() public {
        initializeAndConfig();
        vm.startPrank(OWNER);
        vm.recordLogs();
        indexStaking.setBonusRatePerSecond(address(lbiToken), 2500);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        (,,, uint256 bonusRatePerSecond,,) = indexStaking.tokenPoolInfo(address(lbiToken));
        assertEq(bonusRatePerSecond, 2500);
        assertEq(
            entries[0].topics[0],
            keccak256("BonusRatePerSecondUpdated(address,address,uint256,uint256,uint256,uint256)")
        );
    }

    function test_set_bonus_rate_per_second_fail() public {
        initializeAndConfig();
        vm.startPrank(ACCOUNT_ONE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, ACCOUNT_ONE));
        indexStaking.setBonusRatePerSecond(address(lbiToken), 2400);
        vm.stopPrank();
        vm.startPrank(OWNER);
        MockERC20Token erc20Token = new MockERC20Token("ERC20 Token", "ERC20");
        indexStaking.addStakingPool(address(erc20Token), 2300, block.timestamp + 1 minutes, 5);
        // Pool not exist
        vm.expectRevert("Index Staking: Pool do not exist");
        indexStaking.setBonusRatePerSecond(address(fakeToken), 2990);
        vm.expectRevert("Index Staking: Bonus rate per second must be greater than 0");
        indexStaking.setBonusRatePerSecond(address(erc20Token), 0);
    }

    function test__update_pool() public {
        lockonVesting.addAddressDepositPermission(address(indexStaking));
        IndexStaking.InitPoolInfo memory firstPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(address(lpiToken)), 2300, block.timestamp, 1);
        IndexStaking.InitPoolInfo memory secondPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(address(lbiToken)), 2300, block.timestamp, 2);
        IndexStaking.InitPoolInfo[] memory poolInfos = new IndexStaking.InitPoolInfo[](2);
        poolInfos[0] = firstPoolInfo;
        poolInfos[1] = secondPoolInfo;
        bytes memory indexStakingData = abi.encodeCall(
            indexStaking.initialize,
            (
                OWNER,
                validator,
                address(lockonVesting),
                address(lockToken),
                100000 ether,
                "INDEX_STAKING",
                "1",
                poolInfos
            )
        );
        indexStakingProxy = new ERC1967Proxy(address(indexStaking), indexStakingData);
        indexStaking = IndexStaking(address(indexStakingProxy));
        uint256 depositAmount = 1 ether;

        lbiToken.transfer(address(indexStaking), depositAmount * 2);
        lbiToken.transfer(ACCOUNT_ONE, depositAmount * 2);
        lockToken.transfer(address(indexStaking), 1000 ether);
        lockToken.approve(address(indexStaking), depositAmount * 2);

        vm.stopPrank();
        vm.startPrank(ACCOUNT_ONE);
        lbiToken.approve(address(indexStaking), depositAmount * 2);
        uint256 currentRewardAmount = indexStaking.currentRewardAmount();

        // user first deposit
        indexStaking.deposit(address(lbiToken), depositAmount);
        skip(10 days);
        (,, uint256 lastGeneratedReward, uint256 bonusRatePerSecond, uint256 lastRewardTimestamp,) =
            indexStaking.tokenPoolInfo(address(lbiToken));
        currentRewardAmount = indexStaking.currentRewardAmount();
        indexStaking.updatePool(address(lbiToken));
        indexStaking.deposit(address(lbiToken), depositAmount);
        (,, lastGeneratedReward,, lastRewardTimestamp,) = indexStaking.tokenPoolInfo(address(lbiToken));
        assertEq(lastGeneratedReward, 10 days * currentRewardAmount * bonusRatePerSecond / 2 / 1e12);
        assertEq(lastRewardTimestamp, 10 days + 1);
    }

    function test__update_pool_failed() public {
        lockonVesting.addAddressDepositPermission(address(indexStaking));
        IndexStaking.InitPoolInfo memory firstPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(address(lpiToken)), 2300, block.timestamp, 1);
        IndexStaking.InitPoolInfo memory secondPoolInfo =
            IndexStaking.InitPoolInfo(IERC20(address(lbiToken)), 2300000000, block.timestamp, 2);
        IndexStaking.InitPoolInfo[] memory poolInfos = new IndexStaking.InitPoolInfo[](2);
        poolInfos[0] = firstPoolInfo;
        poolInfos[1] = secondPoolInfo;
        bytes memory indexStakingData = abi.encodeCall(
            indexStaking.initialize,
            (
                OWNER,
                validator,
                address(lockonVesting),
                address(lockToken),
                100000 ether,
                "INDEX_STAKING",
                "1",
                poolInfos
            )
        );
        indexStakingProxy = new ERC1967Proxy(address(indexStaking), indexStakingData);
        indexStaking = IndexStaking(address(indexStakingProxy));
        uint256 depositAmount = 10000 ether;

        lbiToken.transfer(address(indexStaking), depositAmount * 2);
        lbiToken.transfer(ACCOUNT_ONE, depositAmount * 2);
        lpiToken.transfer(address(indexStaking), depositAmount * 2);
        lpiToken.transfer(ACCOUNT_ONE, depositAmount * 2);
        lockToken.transfer(address(indexStaking), 10 ether);
        lockToken.approve(address(indexStaking), depositAmount * 2);

        vm.stopPrank();
        vm.startPrank(ACCOUNT_ONE);
        vm.expectRevert("Index Staking: Pool do not exist");
        indexStaking.updatePool(address(ACCOUNT_THREE));
    }

    function test_view_function() public {
        initializeAndConfig();
        vm.startPrank(OWNER);
        assertEq(indexStaking.rewardTokenPerSecond(address(lpiToken)), 100000 ether * 2300 / 2 / PRECISION);
        assertEq(
            indexStaking.getRewardMultiplier(address(lpiToken), 100, 1000),
            (1000 - 100) * indexStaking.rewardTokenPerSecond(address(lpiToken))
        );
        assertEq(
            indexStaking.getRewardMultiplier(address(lpiToken), 1, 100000 days), indexStaking.currentRewardAmount()
        );
    }

    function test__get_last_generated_reward() public {
        initializeAndConfig();
        vm.startPrank(OWNER);
        uint256 currentRewardAmount = indexStaking.currentRewardAmount();
        assertEq(indexStaking.getLastGeneratedReward(address(lbiToken)), 0);
        uint256 depositAmount = 10 ether;
        lbiToken.transfer(address(indexStaking), depositAmount * 2);
        lbiToken.transfer(ACCOUNT_ONE, depositAmount * 2);
        lockToken.transfer(address(indexStaking), 1000 ether);
        lockToken.approve(address(indexStaking), depositAmount * 2);
        vm.stopPrank();
        vm.startPrank(ACCOUNT_ONE);
        lbiToken.approve(address(indexStaking), depositAmount * 2);

        // user first deposit
        indexStaking.deposit(address(lbiToken), depositAmount);
        indexStaking.getLastGeneratedReward(address(lbiToken));
        (,, uint256 generatedReward, uint256 bonusRatePerSecond, uint256 lastRewardTimestamp,) =
            indexStaking.tokenPoolInfo(address(lbiToken));
        skip(117);
        assertEq(
            indexStaking.getLastGeneratedReward(address(lbiToken)),
            117 * currentRewardAmount * bonusRatePerSecond / 2 / PRECISION
        );
        // Update current reward amount
        currentRewardAmount = indexStaking.currentRewardAmount();
        indexStaking.deposit(address(lbiToken), depositAmount);
        (,, generatedReward,, lastRewardTimestamp,) = indexStaking.tokenPoolInfo(address(lbiToken));
        assertEq(lastRewardTimestamp, 118);
    }

    function test_allocate_token() public {
        initializeAndConfig();
        uint256 lockAmount = 1 ether;
        uint256 oldLockBalance = lockToken.balanceOf(address(indexStaking));
        // Using account one
        vm.startPrank(OWNER);
        vm.recordLogs();
        // Allocate amount of LOCK token
        lockToken.approve(address(indexStaking), lockAmount);
        indexStaking.allocateLockToken(lockAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[2].topics[0], keccak256("LockTokenAllocated(address,uint256)"));
        assertEq(lockToken.balanceOf(address(indexStaking)), oldLockBalance + lockAmount);
    }

    function test_deallocate_token() public {
        initializeAndConfig();
        uint256 lockAmount = 1 ether;
        uint256 oldLockBalance = lockToken.balanceOf(address(indexStaking));
        // Using account one
        vm.startPrank(OWNER);
        vm.recordLogs();
        // Dellocate amount of LOCK token
        lockToken.approve(address(indexStaking), lockAmount);
        indexStaking.deallocateLockToken(lockAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[2].topics[0], keccak256("LockTokenDeallocated(address,uint256)"));
        assertEq(lockToken.balanceOf(address(indexStaking)), oldLockBalance - lockAmount);
    }

    function test_pause_and_unpause() public {
        initializeAndConfig();
        vm.prank(OWNER);
        indexStaking.pause();
        // Cannot do any action when contract is paused
        vm.startPrank(ACCOUNT_ONE);
        uint256 amount = 1 ether;
        vm.expectRevert(EnforcedPause.selector);
        indexStaking.deposit(address(lbiToken), amount);
        vm.expectRevert(EnforcedPause.selector);
        indexStaking.withdraw(address(lbiToken), amount);
        vm.expectRevert(EnforcedPause.selector);
        indexStaking.claimIndexStakingReward("requestId", address(lbiToken), amount, bytes("0x"));
        vm.stopPrank();
        // Transaction can be executed normal when unpause
        vm.prank(OWNER);
        indexStaking.unPause();
        vm.startPrank(ACCOUNT_ONE);
        lpiToken.approve(address(indexStaking), amount);
        indexStaking.deposit(address(lpiToken), amount);
    }

    function test_get_signer_for_request() public {
        initializeAndConfig();
        uint256 claimAmount = 1 ether;
        string memory requestId = "indexStakingClaimOrder#1";
        bytes memory signature = getClaimSignature(requestId, ACCOUNT_ONE, address(lpiToken), claimAmount);
        // Using account one with generated signature
        vm.startPrank(ACCOUNT_ONE);
        lpiToken.approve(address(indexStaking), claimAmount);
        indexStaking.deposit(address(lpiToken), claimAmount);
        address signer =
            indexStaking.getSignerForRequest(requestId, ACCOUNT_ONE, address(lpiToken), claimAmount, signature);
        assertEq(signer, validator);
    }

    function getUserStakedAmount(IndexStaking indexStakingContract, address user, address tokenAddress)
        public
        view
        returns (uint256)
    {
        (uint256 stakedAmount,) = indexStakingContract.userInfo(user, tokenAddress);
        return stakedAmount;
    }

    function test_claim_reward_when_current_reward_amount_is_exhausted() public {
        initializeAndConfig();
        vm.startPrank(OWNER);
        uint256 stakeAmount = 100 ether;
        lockToken.transfer(address(indexStaking), 100000 ether);
        vm.stopPrank();
        vm.startPrank(ACCOUNT_ONE);
        lpiToken.approve(address(indexStaking), stakeAmount);
        indexStaking.deposit(address(lpiToken), stakeAmount);
        vm.stopPrank();

        uint256 currentRewardAmountBefore = indexStaking.currentRewardAmount();
        assertEq(currentRewardAmountBefore, 100000 ether);

        // Calculate reward rate and time needed to generate 99.99% of rewards
        uint256 rewardPerSecond = (100000 ether * 2300) / PRECISION / 2;
        uint256 targetRewardPercentage = 9999; // 99.99%
        uint256 targetRewardAmount = currentRewardAmountBefore * targetRewardPercentage / 10000;
        uint256 skipSeconds = targetRewardAmount / rewardPerSecond;
        skip(skipSeconds);
        indexStaking.updatePool(address(lpiToken));

        uint256 generatedReward = rewardPerSecond * skipSeconds;
        uint256 expectedRemaining = currentRewardAmountBefore - generatedReward;
        uint256 currentRewardAmountAfter = indexStaking.currentRewardAmount();
        assertEq(currentRewardAmountAfter, expectedRemaining);
        assertGt(currentRewardAmountBefore, currentRewardAmountAfter);
        uint256 claimAmount = 11 ether;
        string memory requestId = "indexStakingClaimOrder#1";
        bytes memory signature = getClaimSignature(requestId, ACCOUNT_ONE, address(lpiToken), claimAmount);
        vm.startPrank(ACCOUNT_ONE);
        indexStaking.claimIndexStakingReward(requestId, address(lpiToken), claimAmount, signature);
        vm.stopPrank();
        assertTrue(indexStaking.isRequestIdProcessed(requestId), "Claim should be processed successfully");
    }
}
