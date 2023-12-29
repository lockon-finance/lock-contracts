//SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/ILockonVesting.sol";
/**
 * @title Index Staking contract
 * @author LOCKON
 * @dev A contract that allows users to participate in staking pools to earn rewards.
 * The contract is designed to facilitate the staking of various ERC-20 tokens
 *
 */

contract IndexStaking is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    EIP712Upgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    /* ============ Constants ============== */
    // Represents the category INDEX STAKING in the LOCKON vesting

    uint256 public constant INDEX_STAKING_VESTING_CATEGORY_ID = 1;

    /* ============ Struct ============ */

    // Information about each user's staking in a specific pool
    struct UserInfo {
        uint256 stakedAmount; // The amount staked by the user
        uint256 claimedAmount; // The amount of reward claimed by the user
        uint256 lastStakedTimestamp; // The timestamp of the last staking action by the user
    }

    // Information about each staking pool
    struct PoolInfo {
        IERC20 stakeToken; // The ERC20 token used for staking
        uint256 totalStakedAmount; // The total amount of tokens staked in the pool
        uint256 startTimestamp; // The timestamp at which staking in the pool starts
    }

    // Information about user's claim request
    struct ClaimRequest {
        string requestId; // An ID for the staking reward claim request
        address beneficiary; // The address of the beneficiary of the staking reward
        address stakeToken; // The address of the stake token of the staking pool
        uint256 claimAmount; // The amount of reward tokens to be claimed
    }

    /* ============ Mappings ============ */

    // Mark the order as cancelled
    mapping(string => bool) public isStakingClaimed;

    /* ============ State Variables ============ */

    // Address of the validator
    address public validatorAddress;
    // Address of LOCKON vesting contract
    address public lockonVesting;
    // LOCK token contract used as index staking reward
    IERC20 public lockToken;
    // Timestamp of the last reward distribution
    uint256 public lastRewardDistributionTime;
    // Current amount of reward used to pay for user staking's reward
    uint256 public currentRewardAmount;
    // A mapping to track PoolInfo struct for each stake token address
    mapping(address => PoolInfo) public tokenPoolInfo; // TODO should: Can we use a type that doesn't include the unnecessary `totalStakedAmount` property for initialization?
    // A mapping to track UserInfo for each user in each pool
    mapping(address => mapping(address => UserInfo)) public userInfo;
    // Track the status of each requestId
    mapping(string => bool) public isRequestIdProcessed;

    /* ============ Events ============ */

    /**
     * Emitted when a new staking pool is added
     *
     * @param stakeToken Address of the staked token in the pool
     * @param startTimestamp Timestamp at which the staking pool starts
     */
    event PoolAdded(address stakeToken, uint256 startTimestamp);

    /**
     * Emitted when a user successfully deposits tokens into a staking pool
     *
     * @param sender Address of the function executor
     * @param stakeToken Identifier of the staking pool
     * @param stakeAmount Amount of tokens deposited into the pool
     */
    event DepositSucceeded(address indexed sender, address stakeToken, uint256 stakeAmount);

    /**
     * Emitted when a user successfully withdraws tokens from a staking pool
     *
     * @param sender Address of the function executor
     * @param stakeToken Identifier of the staking pool
     * @param withdrawAmount Amount of tokens withdrawn from the pool
     */
    event WithdrawSucceeded(address indexed sender, address stakeToken, uint256 withdrawAmount);

    /**
     * Emitted when a user claims a staking reward
     *
     * @param sender Address of the function executor
     * @param requestId Identifier for the staking reward claim
     * @param stakeToken Identifier of the staking pool from which the reward is claimed
     * @param claimedAmount Amount of reward tokens claimed
     */
    event IndexStakingRewardClaimed(
        address indexed sender, string requestId, address stakeToken, uint256 claimedAmount
    );

    /**
     * Emitted when a user cancels a staking reward claim order
     *
     * @param sender Address of the function executor
     * @param requestId Identifier for the staking reward claim order being canceled
     * @param stakeToken Identifier of the staking pool for which the claim order is canceled
     */
    event ClaimOrderCancel(address indexed sender, string requestId, address stakeToken);

    /**
     * Emitted when the LOCKON Vesting address is updated
     *
     * @param lockonVesting New LOCKON Vesting address
     * @param timestamp Timestamp at which the address is updated
     */
    event LockonVestingAddressUpdated(address lockonVesting, uint256 timestamp);

    /**
     * Emitted when the validator address is updated
     *
     * @param validator New Validator address
     * @param timestamp Timestamp at which the address is updated
     */
    event ValidatorAddressUpdated(address validator, uint256 timestamp);

    /**
     * @dev Initializes the Index Staking contract with default pools
     *
     * @param _owner Address of the owner of this contract
     * @param _validator Address of the validator of this contract
     * @param _lockonVesting Address of the LOCKON Vesting contract
     * @param _lockToken  Address of the LOCK Token
     * @param _currentRewardAmount  Total amount of reward used to pay for user staking's reward
     * @param _domainName The name of the signing domain
     * @param _signatureVersion  The current major version of the signing domain
     * @param pools Information about the list staking pools
     */
    function initialize(
        address _owner,
        address _validator,
        address _lockonVesting,
        address _lockToken,
        uint256 _currentRewardAmount,
        string memory _domainName,
        string memory _signatureVersion,
        PoolInfo[] calldata pools
    ) external initializer {
        EIP712Upgradeable.__EIP712_init(_domainName, _signatureVersion);
        // Initialize the contract and set the owner
        // This function should be called only once during deployment
        __Ownable_init_unchained(_owner);

        validatorAddress = _validator;
        lockonVesting = _lockonVesting;
        currentRewardAmount = _currentRewardAmount;
        lockToken = IERC20(_lockToken);

        uint256 len = pools.length;
        for (uint256 i = 0; i < len;) {
            IERC20 stakeToken = pools[i].stakeToken;
            require(address(stakeToken) != address(0), "Index Staking: Zero address not allowed");
            tokenPoolInfo[address(stakeToken)] = PoolInfo(stakeToken, 0, pools[i].startTimestamp);
            unchecked {
                i++;
            }
        }
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    /* ============ External Functions ============ */

    /**
     * @notice This function only allows the contract owner to add new staking pool
     * @dev This function is exclusively callable by the owner to define new staking pool for a ERC-20 token
     *
     * @param _stakeToken The address of the ERC-20 token that represents the staking asset in the new pool
     * @param _startTimestamp The starting timestamp from which users can begin staking in this new pool
     */
    function addStakingPool(address _stakeToken, uint256 _startTimestamp) external onlyOwner whenNotPaused {
        require(_stakeToken != address(0), "Index Staking: Zero address not allowed");
        require(tokenPoolInfo[_stakeToken].stakeToken == IERC20(address(0)), "Index Staking: Pool already exist");

        // Add a new pool with the specified ERC-20 token and starting timestamp
        tokenPoolInfo[_stakeToken] = PoolInfo(IERC20(_stakeToken), 0, _startTimestamp);
        emit PoolAdded(_stakeToken, _startTimestamp);
    }

    /**
     * @dev Allows a user to deposit ERC-20 tokens into a specified staking pool
     *
     * @param _stakeToken address of the stake token of the staking pool user wants to deposit
     * @param _stakeAmount The amount of ERC-20 tokens that the user wants to stake in the pool
     */
    function deposit(address _stakeToken, uint256 _stakeAmount) external whenNotPaused {
        require(_stakeAmount > 0, "Index Staking: Stake amount must be greater than 0");
        // Get pool & user information
        PoolInfo storage pool = tokenPoolInfo[_stakeToken];
        UserInfo storage user = userInfo[msg.sender][_stakeToken];
        require(pool.stakeToken != IERC20(address(0)), "Index Staking: Pool not exist");
        // Ensure that staking is allowed for this pool based on the current block timestamp
        require(block.timestamp >= pool.startTimestamp, "Index Staking: Staking not start");
        // Update the user's info
        user.stakedAmount += _stakeAmount;
        user.lastStakedTimestamp = block.timestamp;
        // Transfer the staked tokens from the user to this contract
        pool.stakeToken.safeTransferFrom(msg.sender, address(this), _stakeAmount);
        emit DepositSucceeded(msg.sender, _stakeToken, _stakeAmount);
    }

    /**
     * @dev Allows a user to withdraw staked tokens from a specific staking pool
     *
     * @param _stakeToken address of the stake token of the staking pool user wants to withdraw
     * @param _withdrawAmount The amount of ERC-20 tokens that the user wants to withdraw from the pool
     */
    function withdraw(address _stakeToken, uint256 _withdrawAmount) external whenNotPaused {
        // Get pool & user information
        PoolInfo storage pool = tokenPoolInfo[_stakeToken];
        UserInfo storage user = userInfo[msg.sender][_stakeToken];
        // Check if the withdrawal amount is less than or equal to the user's staked amount
        require(user.stakedAmount >= _withdrawAmount, "Index Staking: Withdrawal amount exceed stake amount");
        // Update the user's staked amount
        user.stakedAmount -= _withdrawAmount;
        // Transfer the withdrawn tokens from the staking pool to the user's address
        pool.stakeToken.safeTransfer(msg.sender, _withdrawAmount);
        emit WithdrawSucceeded(msg.sender, _stakeToken, _withdrawAmount);
    }

    /**
     * @dev Allows a user to claim staking rewards for a specific pool
     *
     * @param _requestId An ID for the staking reward claim
     * @param _stakeToken address of the stake token of the staking pool
     * @param _claimAmount The amount of reward tokens to be claimed
     * @param _signature The signature to validate the claim
     */
    function claimIndexStakingReward(
        string calldata _requestId,
        address _stakeToken,
        uint256 _claimAmount,
        bytes memory _signature
    ) external whenNotPaused nonReentrant {
        UserInfo storage user = userInfo[msg.sender][_stakeToken];
        require(user.lastStakedTimestamp != 0, "Index Staking: User hasn't staked any token yet");
        require(!isRequestIdProcessed[_requestId], "Index Staking: Request already processed");
        require(currentRewardAmount >= _claimAmount, "Index Staking: Claim amount exceed remaining reward");

        // Verify the signature to ensure the validity of the distribution
        require(
            getSignerForRequest(_requestId, msg.sender, _stakeToken, _claimAmount, _signature) == validatorAddress,
            "Index Staking: Invalid signature"
        );
        // Update user claimed amount
        user.claimedAmount += _claimAmount;
        // Mark the requestId as processed to prevent duplicate claim
        isRequestIdProcessed[_requestId] = true;
        // Mark the timestamp of the latest distribution for tracking
        lastRewardDistributionTime = block.timestamp;
        // Subtract the currentReward
        currentRewardAmount -= _claimAmount;
        // Approve for the contract vesting
        lockToken.approve(lockonVesting, _claimAmount);
        // Transfer the reward tokens from the validator to the recipient
        ILockonVesting(lockonVesting).deposit(msg.sender, _claimAmount, INDEX_STAKING_VESTING_CATEGORY_ID);

        emit IndexStakingRewardClaimed(msg.sender, _requestId, _stakeToken, _claimAmount);
    }

    /**
     * @dev Allows a user to cancel a staking reward claim order for a specific pool
     *
     * @param _requestId An ID for the staking reward claim order
     * @param _stakeToken address of the stake token of the staking pool
     * @param _claimAmount The amount of reward tokens in the claim order
     * @param _signature The signature to validate the cancellation
     */
    function cancelClaimOrder(
        string calldata _requestId,
        address _stakeToken,
        uint256 _claimAmount,
        bytes memory _signature
    ) external whenNotPaused {
        UserInfo storage user = userInfo[msg.sender][_stakeToken];
        require(user.lastStakedTimestamp != 0, "Index Staking: User hasn't staked any token yet");

        require(!isRequestIdProcessed[_requestId], "Index Staking: Request already processed");

        // Verify the signature to ensure the validity of the cancellation
        require(
            getSignerForRequest(_requestId, msg.sender, _stakeToken, _claimAmount, _signature) == validatorAddress,
            "Index Staking: Invalid signature"
        );
        // Mark the order as cancelled
        isRequestIdProcessed[_requestId] = true;

        emit ClaimOrderCancel(msg.sender, _requestId, _stakeToken);
    }

    /* ============ PRIVILEGED OWNER / GOVERNANCE Functions ============ */

    /**
     * @notice Pauses the contract, preventing certain functions from being executed.
     * Only the owner can invoke this function.
     */
    function pause() external onlyOwner {
        _pause(); // Calls the internal _pause function from the Pausable library to pause the contract.
    }

    /**
     * @notice Unpauses the contract, allowing normal operation after being paused.
     * Only the owner can invoke this function.
     */
    function unPause() external onlyOwner {
        _unpause(); // Calls the internal _unpause function from the Pausable library to unpause the contract.
    }

    /**
     * @dev Set the address of LOCKON Vesting contract responsible for vested distributed reward
     * @param _lockonVesting  Address of the LOCKON vesting contract
     */
    function setLockonVesting(address _lockonVesting) external onlyOwner {
        require(_lockonVesting != address(0), "Index Staking: Zero address not allowed");
        lockonVesting = _lockonVesting;
        emit LockonVestingAddressUpdated(lockonVesting, block.timestamp);
    }

    /**
     * @dev Set the validator address responsible for reward distribution
     * @param _validatorAddress  Address of the validator
     */
    function setValidatorAddress(address _validatorAddress) external onlyOwner {
        require(_validatorAddress != address(0), "Index Staking: Zero address not allowed");
        validatorAddress = _validatorAddress;
        emit ValidatorAddressUpdated(validatorAddress, block.timestamp);
    }

    /**
     * @dev Override function from UUPS contract for upgrade authorize
     * @param newImplementation  Address of the new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /* ============ Verify signature Functions ============ */

    /**
     * @dev Get signer from data and signature of the staking reward claim or the cancellation claim
     *
     * @param _requestId An ID for the staking reward claim or the cancellation claim
     * @param _stakeToken address of the stake token of the staking pool
     * @param _claimAmount The amount of reward tokens to be claimed
     * @param _signature The signature to validate the claim or cancel claim
     */
    function getSignerForRequest(
        string calldata _requestId,
        address _beneficiary,
        address _stakeToken,
        uint256 _claimAmount,
        bytes memory _signature
    ) public view returns (address) {
        ClaimRequest memory claimRequest = ClaimRequest(_requestId, _beneficiary, _stakeToken, _claimAmount);
        address signer = _verifyClaimRequest(claimRequest, _signature);
        return signer;
    }

    function getDomainSeparator() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @dev Verify the staking reward claim or the cancellation claim request with signature
     *
     * @param _claimRequest An ID for the staking reward claim or the cancellation claim
     * @param _signature The signature to validate the claim
     */
    function _verifyClaimRequest(ClaimRequest memory _claimRequest, bytes memory _signature)
        internal
        view
        returns (address)
    {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256(
                        "ClaimRequest(string requestId,address beneficiary,address stakeToken,uint256 claimAmount)"
                    ),
                    keccak256(bytes(_claimRequest.requestId)),
                    _claimRequest.beneficiary,
                    _claimRequest.stakeToken,
                    _claimRequest.claimAmount
                )
            )
        );
        return ECDSA.recover(digest, _signature);
    }
}
