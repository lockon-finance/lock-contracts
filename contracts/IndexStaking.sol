//SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

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

    /**
     * @dev Represents the scaling factor used in calculations
     */
    uint256 public constant PRECISION = 1e12;
    /**
     * @dev Represents the category INDEX STAKING in the LOCKON vesting
     */
    uint256 public constant INDEX_STAKING_VESTING_CATEGORY_ID = 1;

    /* ============ Struct ============ */

    // Information about each user's staking in a specific pool
    struct UserInfo {
        uint256 stakedAmount; // The amount staked by the user
        uint256 lastStakedTimestamp; // The timestamp of the last staking action by the user
        uint256 rewardDebt; // The reward debt
        uint256 cumulativePendingReward; // Pending reward accumulated each time an user deposit or withdraw
    }

    // Information about each staking pool
    struct PoolInfo {
        IERC20 stakeToken; // The ERC20 token used for staking
        uint256 totalStakedAmount; // The total amount of tokens staked in the pool
        uint256 rewardPerToken; // Accumulated reward per token, times 1e12
        uint256 bonusRatePerSecond; // Bonus rate per second combine with current reward amount to get back reward token per second
        uint256 lastRewardTimestamp; // Last block timestamp that reward distribution in pool occurs
        uint256 startTimestamp; // The timestamp at which staking in the pool starts
    }

    struct InitPoolInfo {
        IERC20 stakeToken; // The ERC20 token used for staking
        uint256 bonusRatePerSecond; // Bonus rate per second combine with current reward amount to get back reward token per second
        uint256 startTimestamp; // The timestamp at which staking in the pool starts
    }

    // Information about user's claim request
    struct ClaimRequest {
        string requestId; // An ID for the staking reward claim request
        address beneficiary; // The address of the beneficiary of the staking reward
        address stakeToken; // The address of the stake token of the staking pool
        uint256 cumulativePendingReward; // Pending reward accumulated each time an user deposit or withdraw
        uint256 claimAmount; // The amount of reward tokens to be claimed
    }

    /* ============ State Variables ============ */
    /**
     * @dev Mapping that keeps track of whether each address is allowed to update current reward amount
     */
    mapping(address => bool) public isAllowedUpdate;
    /**
     * @dev Mapping that keeps track each user address index in the list allowed update address
     */
    mapping(address => uint256) private allowedUpdateOneBasedIndexes;
    /**
     * @dev A mapping to track PoolInfo struct for each stake token address
     */
    mapping(address => PoolInfo) public tokenPoolInfo;
    /**
     * @dev A mapping to track UserInfo for each user in each pool
     */
    mapping(address => mapping(address => UserInfo)) public userInfo;
    /**
     * @dev Track the status of each requestId
     */
    mapping(string => bool) public isRequestIdProcessed;

    /**
     * @dev Address of the validator
     */
    address public validatorAddress;
    /**
     * @dev List address allowed to update the current reward amount of Index staking contract
     */
    address[] public listAllowedUpdate;

    /**
     * @dev Address of LOCKON vesting contract
     */
    address public lockonVesting;
    /**
     * @dev LOCK token contract used as index staking reward
     */
    IERC20 public lockToken;
    /**
     * @dev Current amount of reward used to pay for user staking's reward
     */
    uint256 public currentRewardAmount;
    /**
     * @dev Current total number of pools in index staking
     */
    uint256 public currentNumOfPools;
    /**
     * @dev Reserved storage space to allow for layout changes in the future.
     */
    uint256[50] private __gap;

    /* ============ Events ============ */

    /**
     * Emitted when an user perform action on Index Staking
     *
     * @param sender Address of the function executor
     * @param stakeToken Address of the token user stake
     * @param rewardPerToken Accumulated reward per token
     * @param currentRewardAmount Current amount of reward used to pay for user staking's reward
     * @param lastRewardTimestamp Last block timestamp that reward distribution occurs
     */
    event PoolDataUpdated(
        address indexed sender,
        address stakeToken,
        uint256 rewardPerToken,
        uint256 currentRewardAmount,
        uint256 lastRewardTimestamp
    );

    /**
     * Emitted when a new staking pool is added
     *
     * @param sender Address of the function executor
     * @param stakeToken Address of the staked token in the pool
     * @param bonusRatePerSecond Bonus rate per second combine with current reward amount to get back reward token per second
     * @param currentNumOfPools Current total number of pools in index staking
     * @param startTimestamp Timestamp at which the staking pool starts
     */
    event PoolAdded(
        address indexed sender,
        address stakeToken,
        uint256 bonusRatePerSecond,
        uint256 currentNumOfPools,
        uint256 startTimestamp
    );

    /**
     * Emitted when a user successfully deposits tokens into a staking pool
     *
     * @param sender Address of the function executor
     * @param stakeToken Identifier of the staking pool
     * @param stakeAmount Amount of tokens deposited into the pool
     * @param currentStakedAmount Amount of tokens user staked into the pool
     * @param rewardDebt User's accumulated reward debt
     * @param cumulativePendingReward Pending reward accumulated each time an user deposit or withdraw
     * @param totalStakedAmount The total amount of tokens staked in the pool
     * @param lastRewardTimestamp Last block timestamp that reward distribution occurs
     */
    event DepositSucceeded(
        address indexed sender,
        address stakeToken,
        uint256 stakeAmount,
        uint256 currentStakedAmount,
        uint256 rewardDebt,
        uint256 cumulativePendingReward,
        uint256 totalStakedAmount,
        uint256 lastRewardTimestamp
    );

    /**
     * Emitted when a user successfully withdraws tokens from a staking pool
     *
     * @param sender Address of the function executor
     * @param stakeToken Identifier of the staking pool
     * @param withdrawAmount Amount of tokens withdrawn from the pool
     * @param currentStakedAmount Amount of tokens user staked into the pool
     * @param totalStakedAmount The total amount of tokens staked in the pool
     * @param rewardDebt User's accumulated reward debt
     * @param cumulativePendingReward Pending reward accumulated each time an user deposit or withdraw
     */
    event WithdrawSucceeded(
        address indexed sender,
        address stakeToken,
        uint256 withdrawAmount,
        uint256 currentStakedAmount,
        uint256 totalStakedAmount,
        uint256 rewardDebt,
        uint256 cumulativePendingReward
    );

    /**
     * Emitted when a user claims a staking reward
     *
     * @param sender Address of the function executor
     * @param requestId Identifier for the staking reward claim
     * @param stakeToken Identifier of the staking pool from which the reward is claimed
     * @param claimedAmount Amount of reward tokens claimed
     * @param rewardDebt User's accumulated reward debt
     * @param cumulativePendingReward Pending reward accumulated each time an user deposit or withdraw
     */
    event IndexStakingRewardClaimed(
        address indexed sender,
        string requestId,
        address stakeToken,
        uint256 claimedAmount,
        uint256 rewardDebt,
        uint256 cumulativePendingReward
    );

    /**
     * Emitted when a user cancels a staking reward claim order
     *
     * @param sender Address of the function executor
     * @param requestId Identifier for the staking reward claim order being canceled
     * @param stakeToken Identifier of the staking pool for which the claim order is cancelled
     */
    event ClaimOrderCancel(address indexed sender, string requestId, address stakeToken);

    /**
     * Emitted when the LOCKON Vesting address is updated
     *
     * @param sender Address of the function executor
     * @param lockonVesting New LOCKON Vesting address
     * @param timestamp Timestamp at which the address is updated
     */
    event LockonVestingAddressUpdated(address indexed sender, address lockonVesting, uint256 timestamp);

    /**
     * Emitted when the validator address is updated
     *
     * @param sender Address of the function executor
     * @param validator New Validator address
     * @param timestamp Timestamp at which the address is updated
     */
    event ValidatorAddressUpdated(address indexed sender, address validator, uint256 timestamp);

    /**
     * Emitted when a user set new current reward amount
     *
     * @param sender Address of the function executor
     * @param currentRewardAmount New current reward amount
     * @param timestamp Timestamp at which the currentRewardAmount is updated
     */
    event CurrentRewardAmountUpdated(address indexed sender, uint256 currentRewardAmount, uint256 timestamp);

    /**
     * Emitted when a user set new permissioned address
     *
     * @param sender Address of the function executor
     * @param permissionedAddress New permissioned address
     * @param timestamp Timestamp at which the address is updated
     * @param isPermissionGranted User update permission status
     */
    event PermissionedAddressUpdated(
        address indexed sender, address permissionedAddress, bool isPermissionGranted, uint256 timestamp
    );

    /**
     * Emitted when the bonus rate per second is updated
     *
     * @param sender Address of the function executor
     * @param stakeToken Token address user stake
     * @param bonusRatePerSecond New value for bonus rate per second
     * @param currentRewardAmount New value for current reward amount
     * @param rewardPerToken New value for reward per token
     * @param lastRewardTimestamp New value for last reward timestamp
     * @param timestamp Timestamp at which the address is updated
     */
    event BonusRatePerSecondUpdated(
        address indexed sender,
        address stakeToken,
        uint256 bonusRatePerSecond,
        uint256 currentRewardAmount,
        uint256 rewardPerToken,
        uint256 lastRewardTimestamp,
        uint256 timestamp
    );

    /**
     * @dev Modifier that only owner and address that allowed to update current reward amount can call
     */
    modifier onlyAllowedAddressOrOwner() {
        require(isAllowedUpdate[msg.sender] || msg.sender == owner(), "Index Staking: Forbidden");
        _;
    }

    /**
     * Emitted when the admin allocates an amount of LOCK tokens to the contract
     *
     * @param sender Address of the function executor
     * @param amount Amount of LOCK tokens that are allocated
     */
    event LockTokenAllocated(address indexed sender, uint256 amount);

    /**
     * Emitted when the admin withdraw an amount of LOCK tokens from the contract
     *
     * @param sender Address of the function executor
     * @param amount Amount of LOCK tokens that are deallocated
     */
    event LockTokenDeallocated(address indexed sender, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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
        InitPoolInfo[] calldata pools
    ) external initializer {
        EIP712Upgradeable.__EIP712_init(_domainName, _signatureVersion);
        // Initialize the contract and set the owner
        // This function should be called only once during deployment
        __Ownable_init_unchained(_owner);
        __UUPSUpgradeable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        validatorAddress = _validator;
        lockonVesting = _lockonVesting;
        currentRewardAmount = _currentRewardAmount;
        lockToken = IERC20(_lockToken);

        uint256 len = pools.length;
        for (uint256 i; i < len;) {
            IERC20 stakeToken = pools[i].stakeToken;
            require(address(stakeToken) != address(0), "Index Staking: Zero address not allowed");
            require(
                pools[i].bonusRatePerSecond != 0, "Index Staking: Pool bonus rate per second must be greater than 0"
            );
            tokenPoolInfo[address(stakeToken)] =
                PoolInfo(stakeToken, 0, 0, pools[i].bonusRatePerSecond, block.timestamp, pools[i].startTimestamp);
            unchecked {
                i++;
            }
        }
        currentNumOfPools += len;
    }

    /* ============ View Functions ============ */

    /**
     * @dev Calculates and returns the reward token per second amount
     * @param _stakeToken Stake token address
     */
    function rewardTokenPerSecond(address _stakeToken) public view returns (uint256) {
        PoolInfo storage poolInfo = tokenPoolInfo[_stakeToken];
        return (currentRewardAmount * poolInfo.bonusRatePerSecond) / currentNumOfPools / PRECISION;
    }

    /**
     * @dev Calculates and returns the current reward per token
     * @param _stakeToken Stake token address
     */
    function getCurrentRewardPerToken(address _stakeToken) external view returns (uint256) {
        PoolInfo storage poolInfo = tokenPoolInfo[_stakeToken];
        if (poolInfo.totalStakedAmount == 0) return poolInfo.rewardPerToken;
        // Calculate the reward multiplier based on the difference in block timestamps
        uint256 lockReward = getRewardMultiplier(_stakeToken, poolInfo.lastRewardTimestamp, block.timestamp);
        uint256 rewardPerToken = poolInfo.rewardPerToken;
        rewardPerToken += (lockReward * PRECISION) / poolInfo.totalStakedAmount;
        return rewardPerToken;
    }

    /**
     * @dev Calculates and returns a reward multiplier for a specified time range (`_from` to `_to`)
     * The multiplier is determined by invoking the `rewardTokenPerSecond` function and multiplying it by
     * the time duration between `_from` and `_to`
     * @param _stakeToken Stake token address
     * @param _from The starting timestamp of the time range
     * @param _to The ending timestamp of the time range
     */
    function getRewardMultiplier(address _stakeToken, uint256 _from, uint256 _to) public view returns (uint256) {
        uint256 multiplier = rewardTokenPerSecond(_stakeToken);
        uint256 rewardDistributed = (_to - _from) * multiplier;
        if (rewardDistributed < currentRewardAmount) {
            return rewardDistributed;
        }
        return currentRewardAmount;
    }

    /* ============ Public Functions ============ */

    /**
     * @dev Updates the pool by calculating and distributing rewards to stakers based on the difference in block
     * timestamps between the last reward calculation and the current block. The function adjusts the reward rate
     * per stake token and ensures that the reward distribution does not exceed the available reward supply.
     * The function also updates the last reward block and deducts the distributed rewards from the current reward
     * amount.
     * @param _stakeToken Stake token address
     */
    function updatePool(address _stakeToken) public {
        PoolInfo storage poolInfo = tokenPoolInfo[_stakeToken];
        if (poolInfo.totalStakedAmount == 0) {
            poolInfo.lastRewardTimestamp = block.timestamp;
            return;
        }
        uint256 rewardSupply = lockToken.balanceOf(address(this));
        // Calculate the reward multiplier based on the difference in block timestamps
        uint256 lockReward = getRewardMultiplier(_stakeToken, poolInfo.lastRewardTimestamp, block.timestamp);
        // Ensure that the reward supply is sufficient for the calculated rewards
        require(rewardSupply >= lockReward, "Index Staking: Stake token reward distributed exceed supply");

        // Update state data
        poolInfo.rewardPerToken += (lockReward * PRECISION) / poolInfo.totalStakedAmount;
        currentRewardAmount = currentRewardAmount - lockReward;
        poolInfo.lastRewardTimestamp = block.timestamp;
        emit PoolDataUpdated(
            msg.sender, _stakeToken, poolInfo.rewardPerToken, currentRewardAmount, poolInfo.lastRewardTimestamp
        );
    }

    /* ============ External Functions ============ */

    /**
     * @notice This function only allows the contract owner to add new staking pool
     * @dev This function is exclusively callable by the owner to define new staking pool for a ERC-20 token
     *
     * @param _stakeToken The address of the ERC-20 token that represents the staking asset in the new pool
     * @param _bonusRatePerSecond Bonus rate per second
     * @param _startTimestamp The starting timestamp from which users can begin staking in this new pool
     */
    function addStakingPool(address _stakeToken, uint256 _bonusRatePerSecond, uint256 _startTimestamp)
        external
        onlyOwner
        whenNotPaused
    {
        require(_stakeToken != address(0), "Index Staking: Zero address not allowed");
        require(_bonusRatePerSecond != 0, "Index Staking: Pool bonus rate per second must be greater than 0");
        require(tokenPoolInfo[_stakeToken].stakeToken == IERC20(address(0)), "Index Staking: Pool already exist");

        // Add a new pool with the specified ERC-20 token and starting timestamp
        tokenPoolInfo[_stakeToken] =
            PoolInfo(IERC20(_stakeToken), 0, 0, _bonusRatePerSecond, _startTimestamp, _startTimestamp);
        currentNumOfPools += 1;
        emit PoolAdded(msg.sender, _stakeToken, _bonusRatePerSecond, currentNumOfPools, _startTimestamp);
    }

    /**
     * @dev Allows a user to deposit ERC-20 tokens into a specified staking pool
     *
     * @param _stakeToken address of the stake token of the staking pool user wants to deposit
     * @param _stakeAmount The amount of ERC-20 tokens that the user wants to stake in the pool
     */
    function deposit(address _stakeToken, uint256 _stakeAmount) external whenNotPaused nonReentrant {
        require(_stakeAmount != 0, "Index Staking: Stake amount must be greater than 0");
        // Get pool & user information
        PoolInfo storage pool = tokenPoolInfo[_stakeToken];
        UserInfo storage user = userInfo[msg.sender][_stakeToken];
        require(pool.stakeToken != IERC20(address(0)), "Index Staking: Pool not exist");
        // Ensure that staking is allowed for this pool based on the current block timestamp
        require(block.timestamp >= pool.startTimestamp, "Index Staking: Staking not start");
        updatePool(_stakeToken);
        uint256 pending = (user.stakedAmount * pool.rewardPerToken / PRECISION) - user.rewardDebt;
        if (pending != 0) {
            user.cumulativePendingReward += pending;
        }
        // Update the user's staked amount
        user.stakedAmount += _stakeAmount;
        user.rewardDebt = (user.stakedAmount * pool.rewardPerToken) / PRECISION;
        // Update the pool's info
        pool.totalStakedAmount += _stakeAmount;
        user.lastStakedTimestamp = block.timestamp;
        // Transfer the staked tokens from the user to this contract
        pool.stakeToken.safeTransferFrom(msg.sender, address(this), _stakeAmount);
        emit DepositSucceeded(
            msg.sender,
            _stakeToken,
            _stakeAmount,
            user.stakedAmount,
            user.rewardDebt,
            user.cumulativePendingReward,
            pool.totalStakedAmount,
            user.lastStakedTimestamp
        );
    }

    /**
     * @dev Allows a user to withdraw staked tokens from a specific staking pool
     *
     * @param _stakeToken address of the stake token of the staking pool user wants to withdraw
     * @param _withdrawAmount The amount of ERC-20 tokens that the user wants to withdraw from the pool
     */
    function withdraw(address _stakeToken, uint256 _withdrawAmount) external whenNotPaused nonReentrant {
        require(tokenPoolInfo[_stakeToken].stakeToken != IERC20(address(0)), "Index Staking: Pool do not exist");
        // Get pool & user information
        PoolInfo storage pool = tokenPoolInfo[_stakeToken];
        UserInfo storage user = userInfo[msg.sender][_stakeToken];
        // Check if the withdrawal amount is less than or equal to the user's staked amount
        require(user.stakedAmount >= _withdrawAmount, "Index Staking: Withdrawal amount exceed stake amount");
        updatePool(_stakeToken);
        uint256 pending = (user.stakedAmount * pool.rewardPerToken / PRECISION) - user.rewardDebt;
        if (pending != 0) {
            user.cumulativePendingReward += pending;
        }
        // Update the user's info
        user.stakedAmount -= _withdrawAmount;
        user.rewardDebt = (user.stakedAmount * pool.rewardPerToken) / PRECISION;
        // Update the pool's info
        pool.totalStakedAmount -= _withdrawAmount;
        // Transfer the withdrawn tokens from the staking pool to the user's address
        pool.stakeToken.safeTransfer(msg.sender, _withdrawAmount);
        emit WithdrawSucceeded(
            msg.sender,
            _stakeToken,
            _withdrawAmount,
            user.stakedAmount,
            pool.totalStakedAmount,
            user.rewardDebt,
            user.cumulativePendingReward
        );
    }

    /**
     * @dev Allows a user to claim staking rewards for a specific pool
     *
     * @param _requestId An ID for the staking reward claim
     * @param _stakeToken address of the stake token of the staking pool
     * @param _cumulativePendingReward Pending reward accumulated each time an user deposit or withdraw
     * @param _claimAmount The amount of reward tokens to be claimed
     * @param _signature The signature to validate the claim
     */
    function claimIndexStakingReward(
        string calldata _requestId,
        address _stakeToken,
        uint256 _cumulativePendingReward,
        uint256 _claimAmount,
        bytes memory _signature
    ) external whenNotPaused nonReentrant {
        // Get pool & user information
        PoolInfo storage pool = tokenPoolInfo[_stakeToken];
        UserInfo storage user = userInfo[msg.sender][_stakeToken];
        require(user.lastStakedTimestamp != 0, "Index Staking: User hasn't staked any token yet");
        require(!isRequestIdProcessed[_requestId], "Index Staking: Request already processed");
        require(currentRewardAmount >= _claimAmount, "Index Staking: Claim amount exceed remaining reward");

        // Verify the signature to ensure the validity of the distribution
        require(
            getSignerForRequest(_requestId, msg.sender, _stakeToken, _cumulativePendingReward, _claimAmount, _signature)
                == validatorAddress,
            "Index Staking: Invalid signature"
        );
        updatePool(_stakeToken);
        // Mark the requestId as processed to prevent duplicate claim
        isRequestIdProcessed[_requestId] = true;
        user.cumulativePendingReward -= _cumulativePendingReward;
        user.rewardDebt = (user.stakedAmount * pool.rewardPerToken) / PRECISION;
        // Approve for the contract vesting
        lockToken.approve(lockonVesting, _claimAmount);
        // Transfer the reward tokens from the validator to the recipient
        ILockonVesting(lockonVesting).deposit(msg.sender, _claimAmount, INDEX_STAKING_VESTING_CATEGORY_ID);

        emit IndexStakingRewardClaimed(
            msg.sender, _requestId, _stakeToken, _claimAmount, user.rewardDebt, user.cumulativePendingReward
        );
    }

    /**
     * @dev Allows a user to cancel a staking reward claim order for a specific pool
     *
     * @param _requestId An ID for the staking reward claim order
     * @param _stakeToken address of the stake token of the staking pool
     * @param _cumulativePendingReward Pending reward accumulated each time an user deposit or withdraw
     * @param _claimAmount The amount of reward tokens in the claim order
     * @param _signature The signature to validate the cancellation
     */
    function cancelClaimOrder(
        string calldata _requestId,
        address _stakeToken,
        uint256 _cumulativePendingReward,
        uint256 _claimAmount,
        bytes memory _signature
    ) external whenNotPaused {
        UserInfo storage user = userInfo[msg.sender][_stakeToken];
        require(user.lastStakedTimestamp != 0, "Index Staking: User hasn't staked any token yet");

        require(!isRequestIdProcessed[_requestId], "Index Staking: Request already processed");

        // Verify the signature to ensure the validity of the cancellation
        require(
            getSignerForRequest(_requestId, msg.sender, _stakeToken, _cumulativePendingReward, _claimAmount, _signature)
                == validatorAddress,
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
        emit LockonVestingAddressUpdated(msg.sender, lockonVesting, block.timestamp);
    }

    /**
     * @dev Set the validator address responsible for reward distribution
     * @param _validatorAddress  Address of the validator
     */
    function setValidatorAddress(address _validatorAddress) external onlyOwner {
        require(_validatorAddress != address(0), "Index Staking: Zero address not allowed");
        validatorAddress = _validatorAddress;
        emit ValidatorAddressUpdated(msg.sender, validatorAddress, block.timestamp);
    }

    /**
     * @dev Update the current reward amount value
     * @param _reductionAmount  The amount by which the current reward amount is reduced
     */
    function updateCurrentRewardAmount(uint256 _reductionAmount) external onlyAllowedAddressOrOwner {
        require(_reductionAmount != 0, "Index Staking: Reduction amount must be larger than 0");
        currentRewardAmount -= _reductionAmount;
        emit CurrentRewardAmountUpdated(msg.sender, currentRewardAmount, block.timestamp);
    }

    /**
     * @dev Add address to list address allowed set current reward amount
     * @param _permissionedAddress Address to allow update current reward amount
     */
    function addPermissionedAddress(address _permissionedAddress) external onlyOwner {
        require(_permissionedAddress != address(0), "Index Staking: Zero address not allowed");
        require(
            !isAllowedUpdate[_permissionedAddress], "Index Staking: List allowed address already contains this address"
        );
        listAllowedUpdate.push(_permissionedAddress);
        allowedUpdateOneBasedIndexes[_permissionedAddress] = listAllowedUpdate.length;
        isAllowedUpdate[_permissionedAddress] = true;
        emit PermissionedAddressUpdated(
            msg.sender, _permissionedAddress, isAllowedUpdate[_permissionedAddress], block.timestamp
        );
    }

    /**
     * @dev Remove address from list allowed set current reward amount
     * @param _permissionedAddress Address to remove permission
     */
    function removePermissionedAddress(address _permissionedAddress) external onlyOwner {
        require(_permissionedAddress != address(0), "Index Staking: Zero address not allowed");
        require(
            isAllowedUpdate[_permissionedAddress], "Index Staking: List allowed address does not contain this address"
        );
        uint256 len = listAllowedUpdate.length;
        uint256 index = allowedUpdateOneBasedIndexes[_permissionedAddress];
        address lastValue = listAllowedUpdate[len - 1];
        listAllowedUpdate[index - 1] = lastValue;
        allowedUpdateOneBasedIndexes[lastValue] = index;
        // delete the index
        delete allowedUpdateOneBasedIndexes[_permissionedAddress];
        listAllowedUpdate.pop();
        isAllowedUpdate[_permissionedAddress] = false;
        emit PermissionedAddressUpdated(
            msg.sender, _permissionedAddress, isAllowedUpdate[_permissionedAddress], block.timestamp
        );
    }

    /**
     * @dev Get list address allowed update current reward amount
     */
    function getListAllowedUpdate() external view returns (address[] memory) {
        return listAllowedUpdate;
    }

    /**
     * @dev Allows the owner to set the bonus rate per second for specific pool, influencing the reward token per second calculation
     *
     * @param _stakeToken Stake token address
     * @param _bonusRatePerSecond The new value for the bonus rate
     */
    function setBonusRatePerSecond(address _stakeToken, uint256 _bonusRatePerSecond) external onlyOwner {
        require(_bonusRatePerSecond != 0, "Index Staking: Bonus rate per second must be greater than 0");
        PoolInfo storage pool = tokenPoolInfo[_stakeToken];
        require(pool.stakeToken != IERC20(address(0)), "Index Staking: Pool do not exist");
        updatePool(_stakeToken);
        pool.bonusRatePerSecond = _bonusRatePerSecond;
        emit BonusRatePerSecondUpdated(
            msg.sender,
            _stakeToken,
            pool.bonusRatePerSecond,
            currentRewardAmount,
            pool.rewardPerToken,
            pool.lastRewardTimestamp,
            block.timestamp
        );
    }

    /**
     * @dev Allows the owner to add LOCK tokens to contract Index staking
     *
     * @param _lockAmount The LOCK token amount to be added
     */
    function allocateLockToken(uint256 _lockAmount) external onlyOwner nonReentrant {
        lockToken.safeTransferFrom(msg.sender, address(this), _lockAmount);
        emit LockTokenAllocated(msg.sender, _lockAmount);
    }

    /**
     * @dev Allows the owner to withdraw LOCK tokens from contract Index staking
     *
     * @param _lockAmount The LOCK token amount to be withdrawn
     */
    function deallocateLockToken(uint256 _lockAmount) external onlyOwner nonReentrant {
        lockToken.safeTransfer(msg.sender, _lockAmount);
        emit LockTokenDeallocated(msg.sender, _lockAmount);
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
     * @param _cumulativePendingReward Pending reward accumulated each time an user deposit or withdraw
     * @param _claimAmount The amount of reward tokens to be claimed
     * @param _signature The signature to validate the claim or cancel claim
     */
    function getSignerForRequest(
        string calldata _requestId,
        address _beneficiary,
        address _stakeToken,
        uint256 _cumulativePendingReward,
        uint256 _claimAmount,
        bytes memory _signature
    ) public view returns (address) {
        ClaimRequest memory claimRequest =
            ClaimRequest(_requestId, _beneficiary, _stakeToken, _cumulativePendingReward, _claimAmount);
        address signer = _verifyClaimRequest(claimRequest, _signature);
        return signer;
    }

    /**
     * @dev Return domain separator for Index Staking
     */
    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @dev Verify the staking reward claim or the cancellation claim request with signature
     *
     * @param _claimRequest An ID for the staking reward claim or the cancellation claim
     * @param _signature The signature to validate the claim
     */
    function _verifyClaimRequest(ClaimRequest memory _claimRequest, bytes memory _signature)
        private
        view
        returns (address)
    {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256(
                        "ClaimRequest(string requestId,address beneficiary,address stakeToken,uint256 cumulativePendingReward,uint256 claimAmount)"
                    ),
                    keccak256(bytes(_claimRequest.requestId)),
                    _claimRequest.beneficiary,
                    _claimRequest.stakeToken,
                    _claimRequest.cumulativePendingReward,
                    _claimRequest.claimAmount
                )
            )
        );
        return ECDSA.recover(digest, _signature);
    }
}
