// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {LockonReferral} from "../contracts/LockonReferral.sol";
import {LockonVesting} from "../contracts/LockonVesting.sol";
import {LockToken} from "../contracts/LockToken.sol";
import {LockonReferralSigUtil} from "./LockonReferralSigUtil.sol";
import {MockToken} from "../contracts/MockToken.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract MockLockonReferral is LockonReferral {
    uint256 public counter;

    function setup() public {
        counter = 10;
    }
}

contract LockonReferralTest is Test {
    LockonReferral public referral;
    MockToken public stableToken;
    LockToken public lockToken;
    LockonVesting public lockonVesting;
    LockonReferralSigUtil internal sigUtils;
    ERC1967Proxy stableTokenProxy;
    ERC1967Proxy lockTokenProxy;
    ERC1967Proxy referralProxy;
    ERC1967Proxy lockonVestingProxy;
    uint256[] lockonVestingCategoryIds;
    uint256[] lockonVestingPeriods;
    uint256 constant VALIDATOR_PRIVATE_KEY = 123;
    address public constant OWNER = address(bytes20(bytes("OWNER")));
    address public constant ACCOUNT_ONE = address(1);
    address public constant ACCOUNT_TWO = address(2);
    address public validator = vm.addr(VALIDATOR_PRIVATE_KEY);
    uint256 public constant TEST_ACCOUNT_INITIAL_LOCK_BALANCE = 1000 ether;
    uint256 stableAmount = 1 ether;
    uint256 lockAmount = 1 ether;
    uint256 private constant PRECISION = 1e12;

    error OwnableUnauthorizedAccount(address account);

    error EnforcedPause();

    function setUp() public {
        vm.startPrank(OWNER);
        // lockToken
        bytes memory lockTokenData = abi.encodeCall(lockToken.initialize, ("LockToken", "LOCK", OWNER, validator));
        lockToken = new LockToken();
        lockTokenProxy = new ERC1967Proxy(address(lockToken), lockTokenData);
        lockToken = LockToken(address(lockTokenProxy));
        lockToken.transfer(ACCOUNT_ONE, TEST_ACCOUNT_INITIAL_LOCK_BALANCE);
        lockToken.transfer(ACCOUNT_TWO, TEST_ACCOUNT_INITIAL_LOCK_BALANCE);

        // stableToken
        stableToken = new MockToken("Mock Token", "MTK", OWNER);
        stableToken.mint(ACCOUNT_ONE, TEST_ACCOUNT_INITIAL_LOCK_BALANCE);
        stableToken.mint(ACCOUNT_TWO, TEST_ACCOUNT_INITIAL_LOCK_BALANCE);

        referral = new LockonReferral();
        lockonVesting = new LockonVesting();
        deal(OWNER, 100 ether);
        lockonVestingCategoryIds = new uint256[](3);
        lockonVestingCategoryIds[0] = 10000;
        lockonVestingCategoryIds[1] = 10001;
        lockonVestingCategoryIds[2] = 10002;
        lockonVestingPeriods = new uint256[](3);
        lockonVestingPeriods[0] = 300 days;
        lockonVestingPeriods[1] = 300 days;
        lockonVestingPeriods[2] = 300 days;
    }

    function initializeAndConfig() public {
        bytes memory lockonVestingData = abi.encodeCall(
            lockonVesting.initialize, (ACCOUNT_ONE, address(lockToken), lockonVestingCategoryIds, lockonVestingPeriods)
        );
        lockonVestingProxy = new ERC1967Proxy(address(lockonVesting), lockonVestingData);
        lockonVesting = LockonVesting(address(lockonVestingProxy));
        bytes32[] memory referrlTypes = new bytes32[](0);
        uint256[] memory vestingCategoryIds = new uint256[](0);

        bytes memory referralData = abi.encodeCall(
            referral.initialize,
            (
                OWNER,
                validator, // For testing, use validator as penalty fee receiver also
                address(0),
                address(stableToken),
                address(0),
                referrlTypes,
                vestingCategoryIds
            )
        );
        referralProxy = new ERC1967Proxy(address(referral), referralData);
        referral = LockonReferral(address(referralProxy));
        sigUtils = new LockonReferralSigUtil(referral.getDomainSeparator());
        // Transfer LOCK token to contract for reward distribution
        lockToken.transfer(address(referral), 100000 ether);

        // Transfer stable Token to contract for reward distribution
        stableToken.mint(address(referral), 100000 ether);
        stableToken.mint(OWNER, 100000 ether);
        vm.stopPrank();
        // Approve to pay reward
        vm.prank(validator);
        lockToken.approve(validator, 100000 ether);
        vm.prank(ACCOUNT_ONE);
        lockonVesting.addAddressDepositPermission(address(referral));
    }

    /**
     * @notice Generates a signature from r, s, v values
     * @dev Signature is concatenated in the order of r ++ s ++ v
     * @param r r parameter of the signature
     * @param s s parameter of the signature
     * @param v Recovery ID of the signature
     * @return bytes The generated signature
     */
    function getSignatureFromRSV(bytes32 r, bytes32 s, uint8 v) internal pure returns (bytes memory) {
        return abi.encodePacked(r, s, v);
    }

    /// @notice Helper function to create and sign a claim request
    /// @param requestId Unique identifier for the request
    /// @param beneficiary Address of the beneficiary
    /// @param tokenAddress Address of the token being claimed
    /// @param rewardAmount Amount of tokens to be claimed
    /// @param referralType Type of referral (e.g., "investor", "affiliate")
    /// @return Signature bytes for the claim request
    function createAndSignRequest(
        bytes32 requestId,
        address beneficiary,
        address tokenAddress,
        uint256 rewardAmount,
        bytes32 referralType
    ) private returns (bytes memory) {
        LockonReferralSigUtil.ClaimRequest memory request = LockonReferralSigUtil.ClaimRequest({
            requestId: requestId,
            beneficiary: beneficiary,
            tokenAddress: tokenAddress,
            rewardAmount: rewardAmount,
            referralType: referralType
        });

        bytes32 digest = sigUtils.getTypedDataHash(request);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(VALIDATOR_PRIVATE_KEY, digest);
        return getSignatureFromRSV(r, s, v);
    }

    function test_initialize_fail_owner_zero_address() public {
        bytes32[] memory referralTypes = new bytes32[](0);
        uint256[] memory vestingCategoryIds = new uint256[](0);
        vm.expectRevert("LOCKON Referral: owner is the zero address");
        bytes memory referralData = abi.encodeCall(
            referral.initialize,
            (
                address(0),
                validator, // For testing, use validator as penalty fee receiver also
                address(lockonVesting),
                address(stableToken),
                address(lockToken),
                referralTypes,
                vestingCategoryIds
            )
        );
        referralProxy = new ERC1967Proxy(address(referral), referralData);
        referral = LockonReferral(address(referralProxy));
    }

    function test_initialize_fail_validator_zero_address() public {
        bytes32[] memory referralTypes = new bytes32[](0);
        uint256[] memory vestingCategoryIds = new uint256[](0);
        vm.expectRevert("LOCKON Referral: validator is the zero address");
        bytes memory referralData = abi.encodeCall(
            referral.initialize,
            (
                OWNER,
                address(0), // For testing, use validator as penalty fee receiver also
                address(lockonVesting),
                address(stableToken),
                address(lockToken),
                referralTypes,
                vestingCategoryIds
            )
        );
        referralProxy = new ERC1967Proxy(address(referral), referralData);
        referral = LockonReferral(address(referralProxy));
    }

    function test_initialize_fail_stable_token_zero_address() public {
        bytes32[] memory referralTypes = new bytes32[](0);
        uint256[] memory vestingCategoryIds = new uint256[](0);
        vm.expectRevert("LOCKON Referral: stable token is the zero address");
        bytes memory referralData = abi.encodeCall(
            referral.initialize,
            (
                OWNER,
                validator, // For testing, use validator as penalty fee receiver also
                address(lockonVesting),
                address(0),
                address(lockToken),
                referralTypes,
                vestingCategoryIds
            )
        );
        referralProxy = new ERC1967Proxy(address(referral), referralData);
        referral = LockonReferral(address(referralProxy));
    }

    function test_initialize_fail_referralTypes_and_vestingCategoryIds_not_equal_length() public {
        bytes32[] memory referralTypes = new bytes32[](1);
        referralTypes[0] = "investor";
        uint256[] memory vestingCategoryIds = new uint256[](0);
        vm.expectRevert("LOCKON Referral: The list for referral type and vesting category id must have equal length");
        bytes memory referralData = abi.encodeCall(
            referral.initialize,
            (
                OWNER,
                validator, // For testing, use validator as penalty fee receiver also
                address(lockonVesting),
                address(stableToken),
                address(lockToken),
                referralTypes,
                vestingCategoryIds
            )
        );
        referralProxy = new ERC1967Proxy(address(referral), referralData);
        referral = LockonReferral(address(referralProxy));
    }

    function test_initialize_fail_referralType_is_empty_string() public {
        bytes32[] memory referralTypes = new bytes32[](1);
        referralTypes[0] = "";
        uint256[] memory vestingCategoryIds = new uint256[](1);
        vestingCategoryIds[0] = 10000;
        vm.expectRevert("LOCKON Referral: _referralType is empty not allowed");
        bytes memory referralData = abi.encodeCall(
            referral.initialize,
            (
                OWNER,
                validator, // For testing, use validator as penalty fee receiver also
                address(lockonVesting),
                address(stableToken),
                address(lockToken),
                referralTypes,
                vestingCategoryIds
            )
        );
        referralProxy = new ERC1967Proxy(address(referral), referralData);
        referral = LockonReferral(address(referralProxy));
    }

    function test_initialize_fail_vestingCategoryId_is_zero() public {
        bytes32[] memory referralTypes = new bytes32[](1);
        referralTypes[0] = "investor";
        uint256[] memory vestingCategoryIds = new uint256[](1);
        vestingCategoryIds[0] = 0;
        vm.expectRevert("LOCKON Referral: _vestingCategoryId is 0 not allowed");
        bytes memory referralData = abi.encodeCall(
            referral.initialize,
            (
                OWNER,
                validator, // For testing, use validator as penalty fee receiver also
                address(lockonVesting),
                address(stableToken),
                address(lockToken),
                referralTypes,
                vestingCategoryIds
            )
        );
        referralProxy = new ERC1967Proxy(address(referral), referralData);
        referral = LockonReferral(address(referralProxy));
    }

    function test_initialize() public {
        bytes32[] memory referralTypes = new bytes32[](3);
        referralTypes[0] = bytes32("investor");
        referralTypes[1] = bytes32("affiliate");
        referralTypes[2] = bytes32("special");
        uint256[] memory vestingCategoryIds = new uint256[](3);
        vestingCategoryIds[0] = 10000;
        vestingCategoryIds[1] = 10001;
        vestingCategoryIds[2] = 10002;
        bytes memory referralData = abi.encodeCall(
            referral.initialize,
            (
                OWNER,
                validator, // For testing, use validator as penalty fee receiver also
                address(lockonVesting),
                address(stableToken),
                address(lockToken),
                referralTypes,
                vestingCategoryIds
            )
        );
        referralProxy = new ERC1967Proxy(address(referral), referralData);
        referral = LockonReferral(address(referralProxy));

        assertEq(referral.referralTypeToVestingCategoryId(referralTypes[0]), vestingCategoryIds[0]);
        assertEq(referral.referralTypeToVestingCategoryId(referralTypes[1]), vestingCategoryIds[1]);
        assertEq(referral.referralTypeToVestingCategoryId(referralTypes[2]), vestingCategoryIds[2]);
    }

    function test_set_validator_fail() public {
        bytes memory lockonVestingData = abi.encodeCall(
            lockonVesting.initialize, (ACCOUNT_ONE, address(lockToken), lockonVestingCategoryIds, lockonVestingPeriods)
        );
        lockonVestingProxy = new ERC1967Proxy(address(lockonVesting), lockonVestingData);
        lockonVesting = LockonVesting(address(lockonVestingProxy));
        bytes32[] memory referralTypes = new bytes32[](0);
        uint256[] memory vestingCategoryIds = new uint256[](0);
        bytes memory referralData = abi.encodeCall(
            referral.initialize,
            (
                OWNER,
                validator, // For testing, use validator as penalty fee receiver also
                address(lockonVesting),
                address(stableToken),
                address(lockToken),
                referralTypes,
                vestingCategoryIds
            )
        );
        referralProxy = new ERC1967Proxy(address(referral), referralData);
        referral = LockonReferral(address(referralProxy));
        vm.startPrank(OWNER);
        vm.expectRevert("LOCKON Referral: Zero address not allowed");
        // Set validator address
        referral.setValidatorAddress(address(0));
    }

    function test_set_lockon_vesting_address() public {
        initializeAndConfig();
        vm.prank(OWNER);
        vm.recordLogs();
        referral.setLockonVesting(ACCOUNT_ONE);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(referral.lockonVestingAddress(), ACCOUNT_ONE);
        assertEq(entries[0].topics[0], keccak256("LockonVestingUpdated(address,address,uint256)"));
    }

    function test_set_lockon_vesting_address_fail() public {
        initializeAndConfig();
        vm.prank(ACCOUNT_ONE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, ACCOUNT_ONE));
        referral.setLockonVesting(ACCOUNT_ONE);
        vm.expectRevert("LOCKON Referral: Zero address not allowed");
        vm.prank(OWNER);
        referral.setLockonVesting(address(0));
    }

    function test_set_lock_token() public {
        initializeAndConfig();
        vm.prank(OWNER);
        vm.recordLogs();
        referral.setLockTokenAddress(address(lockToken));
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(referral.lockTokenAddress(), address(lockToken));
        assertEq(entries[0].topics[0], keccak256("LockTokenUpdated(address,address,uint256)"));
    }

    function test_set_lock_token_fail() public {
        initializeAndConfig();
        vm.prank(OWNER);
        vm.expectRevert("LOCKON Referral: Zero address not allowed");
        referral.setLockTokenAddress(address(0));
    }

    function test_set_stable_token() public {
        initializeAndConfig();
        vm.prank(OWNER);
        vm.recordLogs();
        referral.setStableTokenAddress(address(stableToken));
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(referral.stableTokenAddress(), address(stableToken));
        assertEq(entries[0].topics[0], keccak256("StableTokenUpdated(address,address,uint256)"));
    }

    function test_set_stable_token_fail() public {
        initializeAndConfig();
        vm.prank(OWNER);
        vm.expectRevert("LOCKON Referral: Zero address not allowed");
        referral.setStableTokenAddress(address(0));
    }

    function test_set_referral_type_to_vesting_categoryId() public {
        initializeAndConfig();
        vm.prank(OWNER);
        vm.recordLogs();
        bytes32 referralType = bytes32("investor");
        referral.setReferralTypeToVestingCategoryId(referralType, 10000);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(referral.referralTypeToVestingCategoryId(referralType), 10000);
        assertEq(entries[0].topics[0], keccak256("ReferralTypeToVestingCategoryIdUpdated(bytes32,uint256)"));
    }

    function test_set_referral_type_to_vesting_categoryId_fail() public {
        initializeAndConfig();
        vm.prank(OWNER);
        bytes32 referralType = bytes32("");
        vm.expectRevert("LOCKON Referral: _referralType is empty not allowed");
        referral.setReferralTypeToVestingCategoryId(referralType, 10000);
    }

    function test_delete_referral_type_to_vesting_categoryId() public {
        initializeAndConfig();
        vm.prank(OWNER);
        vm.recordLogs();
        bytes32 referralType = bytes32("investor");
        referral.setReferralTypeToVestingCategoryId(referralType, 0);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(referral.referralTypeToVestingCategoryId(referralType), 0);
        assertEq(entries[0].topics[0], keccak256("ReferralTypeToVestingCategoryIdDeleted(bytes32,uint256)"));
    }

    function test_allocate_token() public {
        initializeAndConfig();
        uint256 oldLockBalance = lockToken.balanceOf(address(referral));
        vm.startPrank(OWNER);
        referral.setLockTokenAddress(address(lockToken));
        vm.recordLogs();
        lockToken.approve(address(referral), lockAmount);
        referral.allocateRewardToken(address(lockToken), lockAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[2].topics[0], keccak256("RewardTokenAllocated(address,address,uint256)"));
        assertEq(lockToken.balanceOf(address(referral)), oldLockBalance + lockAmount);
    }

    function test_allocate_erc20_token() public {
        initializeAndConfig();
        uint256 oldLockBalance = stableToken.balanceOf(address(referral));
        vm.startPrank(OWNER);
        vm.recordLogs();
        stableToken.approve(address(referral), stableAmount);
        referral.allocateRewardToken(address(stableToken), stableAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[2].topics[0], keccak256("RewardTokenAllocated(address,address,uint256)"));
        assertEq(stableToken.balanceOf(address(referral)), oldLockBalance + stableAmount);
    }

    function test_allocate_token_fail() public {
        initializeAndConfig();
        vm.startPrank(OWNER);

        vm.expectRevert("LOCKON Referral: _tokenAddress not supported");
        referral.allocateRewardToken(ACCOUNT_ONE, lockAmount);

        vm.expectRevert("LOCKON Referral: Zero address not allowed");
        referral.allocateRewardToken(address(0), lockAmount);

        referral.setLockTokenAddress(address(lockToken));
        vm.expectRevert("LOCKON Referral: _amount must be greater than Zero");
        referral.allocateRewardToken(address(lockToken), 0);
    }

    function test_deallocate_token() public {
        initializeAndConfig();
        uint256 oldLockBalance = lockToken.balanceOf(address(referral));
        vm.startPrank(OWNER);
        referral.setLockTokenAddress(address(lockToken));
        vm.recordLogs();
        lockToken.approve(address(referral), lockAmount);
        referral.deallocateRewardToken(address(lockToken), lockAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[2].topics[0], keccak256("RewardTokenDeallocated(address,address,uint256)"));
        assertEq(lockToken.balanceOf(address(referral)), oldLockBalance - lockAmount);
    }

    function test_deallocate_erc20_token() public {
        initializeAndConfig();
        uint256 oldLockBalance = stableToken.balanceOf(address(referral));
        vm.startPrank(OWNER);
        vm.recordLogs();
        stableToken.approve(address(referral), stableAmount);
        referral.deallocateRewardToken(address(stableToken), stableAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[2].topics[0], keccak256("RewardTokenDeallocated(address,address,uint256)"));
        assertEq(stableToken.balanceOf(address(referral)), oldLockBalance - stableAmount);
    }

    function test_deallocate_token_fail() public {
        initializeAndConfig();
        vm.startPrank(OWNER);

        vm.expectRevert("LOCKON Referral: _tokenAddress not supported");
        referral.deallocateRewardToken(ACCOUNT_ONE, lockAmount);

        vm.expectRevert("LOCKON Referral: Zero address not allowed");
        referral.deallocateRewardToken(address(0), lockAmount);

        referral.setLockTokenAddress(address(lockToken));
        vm.expectRevert("LOCKON Referral: _amount must be greater than Zero");
        referral.deallocateRewardToken(address(lockToken), 0);
    }

    function test_get_signer_for_request() public {
        initializeAndConfig();
        uint256 rewardAmount = 10 ether;
        bytes32 requestId = "referralClaimOrder#2";
        bytes memory signature =
            createAndSignRequest(requestId, ACCOUNT_ONE, address(lockToken), rewardAmount, "investor");

        vm.startPrank(ACCOUNT_ONE);
        address signer = referral.getSignerForRequest(
            requestId, ACCOUNT_ONE, address(lockToken), rewardAmount, "investor", signature
        );
        assertEq(signer, validator);
    }

    function test_get_signer_for_cancel_request() public {
        initializeAndConfig();
        bytes32 requestId = "referralClaimOrder#2";
        bytes memory signature = createAndSignRequest(requestId, ACCOUNT_ONE, address(lockToken), 1, "investor");

        vm.startPrank(ACCOUNT_ONE);
        address signer =
            referral.getSignerForRequest(requestId, ACCOUNT_ONE, address(lockToken), 1, "investor", signature);
        assertEq(signer, validator);
    }

    function test_pause_and_unpause() public {
        initializeAndConfig();
        uint256 accountOneBalanceBefore = stableToken.balanceOf(ACCOUNT_ONE);
        vm.startPrank(OWNER);
        bytes32 referralType = bytes32("investor");
        referral.setReferralTypeToVestingCategoryId(referralType, 10000);
        referral.pause();
        // Cannot do any action when contract is paused
        vm.startPrank(ACCOUNT_ONE);
        uint256 rewardAmount = 20 ether;
        bytes32 requestId = "referralClaimOrder#1";
        bytes memory signature =
            createAndSignRequest(requestId, ACCOUNT_ONE, address(stableToken), rewardAmount, referralType);
        vm.expectRevert(EnforcedPause.selector);
        referral.claimPendingReward(requestId, address(stableToken), rewardAmount, referralType, signature);
        vm.stopPrank();
        // Transaction can be executed normal when unpause
        vm.prank(OWNER);
        referral.unpause();
        vm.startPrank(ACCOUNT_ONE);
        referral.claimPendingReward(requestId, address(stableToken), rewardAmount, referralType, signature);
        assertEq(stableToken.balanceOf(ACCOUNT_ONE), accountOneBalanceBefore + rewardAmount);
    }

    function test_set_functions() public {
        initializeAndConfig();
        vm.startPrank(OWNER);
        vm.recordLogs();
        referral.setValidatorAddress(ACCOUNT_TWO);
        assertEq(referral.validatorAddress(), ACCOUNT_TWO);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("ValidatorAddressUpdated(address,address,uint256)"));
    }

    function test_upgrade_referral() public {
        initializeAndConfig();

        bytes32 referralType = bytes32("investor");
        uint256 vestingCategoryId = 10000;
        vm.prank(OWNER);
        referral.setReferralTypeToVestingCategoryId(referralType, vestingCategoryId);

        performUpgrade();

        checkAfterUpgrade(referralType, vestingCategoryId);

        checkExistingFunctionality();
    }

    function performUpgrade() private {
        vm.startPrank(OWNER);
        MockLockonReferral mock = new MockLockonReferral();
        bytes memory data = abi.encodeCall(mock.setup, ());
        UUPSUpgradeable(referral).upgradeToAndCall(address(mock), data);
        vm.stopPrank();
    }

    function checkAfterUpgrade(bytes32 referralType, uint256 vestingCategoryId) private {
        assertEq(MockLockonReferral(payable(referralProxy)).counter(), 10);
        assertEq(referral.referralTypeToVestingCategoryId(referralType), vestingCategoryId);
    }

    function checkExistingFunctionality() private {
        vm.prank(OWNER);
        referral.setValidatorAddress(ACCOUNT_TWO);
        assertEq(referral.validatorAddress(), ACCOUNT_TWO);
    }

    function test_revert_on_deposit_vesting() public {
        bytes memory lockonVestingData = abi.encodeCall(
            lockonVesting.initialize, (ACCOUNT_ONE, address(lockToken), lockonVestingCategoryIds, lockonVestingPeriods)
        );
        lockonVestingProxy = new ERC1967Proxy(address(lockonVesting), lockonVestingData);
        lockonVesting = LockonVesting(address(lockonVestingProxy));
        bytes32[] memory referralTypes = new bytes32[](0);
        uint256[] memory vestingCategoryIds = new uint256[](0);
        bytes memory referralData = abi.encodeCall(
            referral.initialize,
            (
                OWNER,
                validator, // For testing, use validator as penalty fee receiver also
                address(lockonVesting),
                address(stableToken),
                address(lockToken),
                referralTypes,
                vestingCategoryIds
            )
        );
        referralProxy = new ERC1967Proxy(address(referral), referralData);
        referral = LockonReferral(address(referralProxy));
        bytes32 referralType = bytes32("investor");
        referral.setReferralTypeToVestingCategoryId(referralType, 10000);
        sigUtils = new LockonReferralSigUtil(referral.getDomainSeparator());

        // Initalize signature for claim reward
        uint256 rewardAmount = 20 ether;
        bytes32 requestId = "referralClaimOrder#1";
        bytes memory signature =
            createAndSignRequest(requestId, ACCOUNT_ONE, address(lockToken), rewardAmount, referralType);
        // Transfer LOCK token to contract for reward distribution
        lockToken.transfer(address(referral), 100000 ether);
        // Using account one
        vm.startPrank(ACCOUNT_ONE);
        // Since the Referral contract is not set, all next tx will be revert
        vm.expectRevert("LOCKON Vesting: Forbidden");
        referral.claimPendingReward(requestId, address(lockToken), rewardAmount, referralType, signature);
    }

    function test_claim_pending_reward() public {
        initializeAndConfig();
        vm.startPrank(ACCOUNT_ONE);
        uint256[] memory vestingCategoryIds = new uint256[](1);
        vestingCategoryIds[0] = 10000;
        uint256[] memory vestingCategoryValues = new uint256[](1);
        vestingCategoryValues[0] = 100 days;
        lockonVesting.setVestingCategories(vestingCategoryIds, vestingCategoryValues);

        vm.startPrank(OWNER);
        referral.setLockTokenAddress(address(lockToken));
        referral.setLockonVesting(address(lockonVesting));
        bytes32 referralType = bytes32("investor");
        referral.setReferralTypeToVestingCategoryId(referralType, 10000);

        uint256 rewardAmount = 20 ether;
        bytes32 requestId = bytes32("referralClaimOrder#1");
        bytes memory signature =
            createAndSignRequest(requestId, ACCOUNT_ONE, address(lockToken), rewardAmount, referralType);

        vm.startPrank(ACCOUNT_ONE);
        uint256 lockonVestingBalanceBefore = lockToken.balanceOf(address(lockonVesting));
        vm.recordLogs();
        referral.claimPendingReward(requestId, address(lockToken), rewardAmount, referralType, signature);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(lockToken.balanceOf(address(lockonVesting)), lockonVestingBalanceBefore + rewardAmount);
        assertEq(entries[3].topics[0], keccak256("ClaimedReferralReward(address,bytes32,address,uint256,bytes32)"));
    }

    function test_claim_pending_erc20_reward() public {
        initializeAndConfig();
        vm.prank(OWNER);
        bytes32 referralType = bytes32("affiliate");
        referral.setReferralTypeToVestingCategoryId(referralType, 10001);
        uint256 rewardAmount = 20 ether;
        bytes32 requestId = bytes32("referralClaimOrder#1");
        bytes memory signature =
            createAndSignRequest(requestId, ACCOUNT_ONE, address(stableToken), rewardAmount, referralType);

        vm.startPrank(ACCOUNT_ONE);
        uint256 accountOneBalanceBefore = stableToken.balanceOf(ACCOUNT_ONE);
        vm.recordLogs();
        referral.claimPendingReward(requestId, address(stableToken), rewardAmount, referralType, signature);
        vm.roll(block.number + 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(stableToken.balanceOf(ACCOUNT_ONE), accountOneBalanceBefore + rewardAmount);
        assertEq(entries[1].topics[0], keccak256("ClaimedReferralReward(address,bytes32,address,uint256,bytes32)"));
    }

    function test_claim_pending_reward_fail() public {
        initializeAndConfig();
        vm.prank(OWNER);
        bytes32 referralType = bytes32("special");
        referral.setReferralTypeToVestingCategoryId(referralType, 10002);
        vm.startPrank(ACCOUNT_ONE);
        uint256[] memory vestingCategoryIds = new uint256[](1);
        vestingCategoryIds[0] = 10002;
        uint256[] memory vestingCategoryValues = new uint256[](1);
        vestingCategoryValues[0] = 300 days;
        lockonVesting.setVestingCategories(vestingCategoryIds, vestingCategoryValues);

        uint256 rewardAmount = 20 ether;
        bytes32 requestId = "referralClaimOrder#1";
        bytes memory signature =
            createAndSignRequest(requestId, ACCOUNT_ONE, address(lockToken), rewardAmount, referralType);

        vm.startPrank(ACCOUNT_ONE);
        vm.expectRevert("LOCKON Referral: _tokenAddress not supported");
        referral.claimPendingReward(requestId, address(lockToken), rewardAmount, referralType, signature);

        vm.startPrank(OWNER);
        referral.setLockTokenAddress(address(lockToken));
        vm.startPrank(ACCOUNT_ONE);
        vm.expectRevert("LOCKON Referral: lockonVestingAddress is the zero address");
        referral.claimPendingReward(requestId, address(lockToken), rewardAmount, referralType, signature);

        vm.startPrank(OWNER);
        referral.setLockonVesting(address(lockonVesting));
        referral.deallocateRewardToken(address(lockToken), 100000 ether);
        vm.startPrank(ACCOUNT_ONE);
        vm.expectRevert("LOCKON Referral: Insufficient funds contract");
        referral.claimPendingReward(requestId, address(lockToken), rewardAmount, referralType, signature);

        vm.expectRevert("LOCKON Referral: Invalid signature");
        referral.claimPendingReward(requestId, address(lockToken), rewardAmount + 1, referralType, signature);

        vm.expectRevert("LOCKON Referral: _referralType not supported");
        referral.claimPendingReward(requestId, address(lockToken), rewardAmount + 1, "a", signature);

        vm.expectRevert("LOCKON Referral: _tokenAddress is the zero address");
        referral.claimPendingReward(requestId, address(0), rewardAmount, referralType, signature);

        vm.expectRevert("LOCKON Referral: _rewardAmount must be greater than Zero");
        referral.claimPendingReward(requestId, address(lockToken), 0, referralType, signature);

        vm.startPrank(OWNER);
        lockToken.approve(address(referral), 100 ether);
        referral.allocateRewardToken(address(lockToken), 100 ether);
        vm.startPrank(ACCOUNT_ONE);
        referral.claimPendingReward(requestId, address(lockToken), rewardAmount, referralType, signature);
        vm.expectRevert("LOCKON Referral: Request already processed");
        referral.claimPendingReward(requestId, address(lockToken), rewardAmount, referralType, signature);
    }

    function test_claim_pending_erc20_reward_fail() public {
        initializeAndConfig();
        vm.prank(OWNER);
        bytes32 referralType = bytes32("affiliate");
        referral.setReferralTypeToVestingCategoryId(referralType, 10001);
        vm.startPrank(ACCOUNT_ONE);
        uint256[] memory vestingCategoryIds = new uint256[](1);
        vestingCategoryIds[0] = 10001;
        uint256[] memory vestingCategoryValues = new uint256[](1);
        vestingCategoryValues[0] = 300 days;
        lockonVesting.setVestingCategories(vestingCategoryIds, vestingCategoryValues);

        uint256 rewardAmount = 20 ether;
        bytes32 requestId = "referralClaimOrder#1";
        bytes memory signature =
            createAndSignRequest(requestId, ACCOUNT_ONE, address(stableToken), rewardAmount, referralType);

        vm.startPrank(ACCOUNT_ONE);
        vm.expectRevert("LOCKON Referral: _tokenAddress not supported");
        referral.claimPendingReward(requestId, address(lockToken), rewardAmount, referralType, signature);
        vm.stopPrank();

        vm.startPrank(OWNER);
        referral.deallocateRewardToken(address(stableToken), 100000 ether);
        vm.stopPrank();
        vm.startPrank(ACCOUNT_ONE);
        vm.expectRevert("LOCKON Referral: Insufficient funds contract");
        referral.claimPendingReward(requestId, address(stableToken), rewardAmount, referralType, signature);

        vm.expectRevert("LOCKON Referral: Invalid signature");
        referral.claimPendingReward(requestId, address(stableToken), rewardAmount + 1, referralType, signature);

        vm.expectRevert("LOCKON Referral: _referralType not supported");
        referral.claimPendingReward(requestId, address(stableToken), rewardAmount + 1, "a", signature);

        vm.expectRevert("LOCKON Referral: _tokenAddress is the zero address");
        referral.claimPendingReward(requestId, address(0), rewardAmount, referralType, signature);

        vm.expectRevert("LOCKON Referral: _rewardAmount must be greater than Zero");
        referral.claimPendingReward(requestId, address(stableToken), 0, referralType, signature);

        vm.startPrank(OWNER);
        stableToken.approve(address(referral), 100 ether);
        referral.allocateRewardToken(address(stableToken), 100 ether);
        vm.stopPrank();
        vm.startPrank(ACCOUNT_ONE);
        referral.claimPendingReward(requestId, address(stableToken), rewardAmount, referralType, signature);
        vm.expectRevert("LOCKON Referral: Request already processed");
        referral.claimPendingReward(requestId, address(stableToken), rewardAmount, referralType, signature);
    }

    function test_cancel_claim_order_normal_case() public {
        initializeAndConfig();
        vm.startPrank(OWNER);
        bytes32 referralType = bytes32("investor");
        referral.setReferralTypeToVestingCategoryId(referralType, 10001);
        referral.setLockTokenAddress(address(lockToken));
        uint256 rewardAmount = 1 ether;

        bytes32 requestId = keccak256(abi.encodePacked("cancelClaimOrder#1"));
        vm.startPrank(ACCOUNT_ONE);
        vm.recordLogs();

        bytes memory signature =
            createAndSignRequest(requestId, ACCOUNT_ONE, address(lockToken), rewardAmount, referralType);
        referral.cancelClaimOrder(requestId, address(lockToken), rewardAmount, referralType, signature);

        // Verify that a cancelled request cannot be claimed
        vm.expectRevert("LOCKON Referral: Request already processed");
        referral.claimPendingReward(requestId, address(lockToken), rewardAmount, referralType, signature);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("ClaimOrderCanceled(address,bytes32,address,uint256,bytes32)"));
        vm.stopPrank();
    }

    function test_cancel_claim_order_unsupported_token() public {
        initializeAndConfig();
        vm.startPrank(OWNER);
        bytes32 referralType = bytes32("investor");
        referral.setReferralTypeToVestingCategoryId(referralType, 10001);
        referral.setLockTokenAddress(address(lockToken));
        uint256 rewardAmount = 1 ether;

        bytes32 requestId = keccak256(abi.encodePacked("cancelClaimOrder#2"));
        vm.startPrank(ACCOUNT_ONE);
        vm.recordLogs();

        bytes memory signature = createAndSignRequest(requestId, ACCOUNT_ONE, address(0), rewardAmount, referralType);
        referral.cancelClaimOrder(requestId, address(0), rewardAmount, referralType, signature);

        // Verify that a cancelled request cannot be claimed
        vm.expectRevert("LOCKON Referral: Request already processed");
        referral.claimPendingReward(requestId, address(lockToken), rewardAmount, referralType, signature);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("ClaimOrderCanceled(address,bytes32,address,uint256,bytes32)"));
        vm.stopPrank();
    }

    function test_cancel_claim_order_unsupported_type() public {
        initializeAndConfig();
        vm.startPrank(OWNER);
        bytes32 referralType = bytes32("investor");
        referral.setReferralTypeToVestingCategoryId(referralType, 10001);
        referral.setLockTokenAddress(address(lockToken));
        uint256 rewardAmount = 1 ether;

        bytes32 requestId = keccak256(abi.encodePacked("cancelClaimOrder#3"));
        vm.startPrank(ACCOUNT_ONE);
        vm.recordLogs();

        bytes32 unsupportedType = bytes32("unsupported_type");
        bytes memory signature =
            createAndSignRequest(requestId, ACCOUNT_ONE, address(lockToken), rewardAmount, unsupportedType);
        referral.cancelClaimOrder(requestId, address(lockToken), rewardAmount, unsupportedType, signature);

        // Verify that a cancelled request cannot be claimed
        vm.expectRevert("LOCKON Referral: Request already processed");
        referral.claimPendingReward(requestId, address(lockToken), rewardAmount, referralType, signature);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("ClaimOrderCanceled(address,bytes32,address,uint256,bytes32)"));
        vm.stopPrank();
    }

    function test_cancel_claim_order_zero_amount() public {
        initializeAndConfig();
        vm.startPrank(OWNER);
        bytes32 referralType = bytes32("investor");
        referral.setReferralTypeToVestingCategoryId(referralType, 10001);
        referral.setLockTokenAddress(address(lockToken));
        uint256 rewardAmount = 1 ether;

        bytes32 requestId = keccak256(abi.encodePacked("cancelClaimOrder#4"));
        vm.startPrank(ACCOUNT_ONE);
        vm.recordLogs();

        bytes memory signature = createAndSignRequest(requestId, ACCOUNT_ONE, address(lockToken), 0, referralType);
        referral.cancelClaimOrder(requestId, address(lockToken), 0, referralType, signature);

        // Verify that a cancelled request cannot be claimed
        vm.expectRevert("LOCKON Referral: Request already processed");
        referral.claimPendingReward(requestId, address(lockToken), rewardAmount, referralType, signature);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("ClaimOrderCanceled(address,bytes32,address,uint256,bytes32)"));
        vm.stopPrank();
    }

    function test_cancel_claim_order_fail() public {
        initializeAndConfig();
        vm.startPrank(OWNER);
        bytes32 referralType = bytes32("affiliate");
        referral.setReferralTypeToVestingCategoryId(referralType, 10001);
        bytes32 requestId = "referralClaimOrder#1";
        uint256 rewardAmount = 1 ether;

        bytes memory signature =
            createAndSignRequest(requestId, ACCOUNT_ONE, address(stableToken), rewardAmount, referralType);

        vm.startPrank(ACCOUNT_ONE);
        vm.expectRevert("LOCKON Referral: Invalid signature");
        referral.cancelClaimOrder(requestId, address(stableToken), rewardAmount + 1, referralType, signature);

        // Case with cancelled request
        referral.cancelClaimOrder(requestId, address(stableToken), rewardAmount, referralType, signature);
        vm.expectRevert("LOCKON Referral: Request already processed");
        referral.cancelClaimOrder(requestId, address(stableToken), rewardAmount, referralType, signature);
    }
}
