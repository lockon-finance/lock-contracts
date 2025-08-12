//SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "./interfaces/ILockonVesting.sol";

/**
 * @title LOCK Staking contract
 * @author LOCKON
 * @dev Allows users to stake LOCK Token and claim rewards
 *
 */
contract LockStaking is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    EIP712Upgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    /* ============ Struct ============ */
    // Info of each user.

    struct UserInfo {
        uint256 lockedAmount; // How many LOCK Token the user has locked
        uint256 lockScore; // How many LOCK Score that user currently possess
        uint256 lockDuration; // Duration of the lock
        uint256 lastBasicRate; // The basic rate of user when the tokens were last locked
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 lockEndTimestamp; // Timestamp on which the lock duration end
        uint256 cumulativePendingReward; // Pending reward accumulated each time an user deposit/withdraw/extend duration
    }
    // The staking logic is heavily inspired by SushiSwap’s MasterChef contract,
    // here is an explanation of the `rewardDebt` parameter:
    // Basically, any point in time, the amount of reward token
    // entitled to a user but is pending to be distributed is:
    //
    //    pending reward = (user.score * rewardPerScore) - user.rewardDebt
    //
    // Whenever a user add, extend or withdraws LOCK tokens to contract. Here's what happens:
    //   1. The contract's `rewardPerScore` (and `lastRewardTimestamp`) gets updated.
    //   2. Calculate user's pending reward, this amount will be accumulated in
    //       user's `cumulativePendingReward`
    //   3. User's `lockedAmount` gets updated.
    //   4. User's `rewardDebt` gets updated.

    // Reward claim request
    struct ClaimRequest {
        string requestId; // An ID for the reward claim request
        address beneficiary; // The address of the beneficiary
        uint256 rewardAmount; // The amount of reward tokens to be claimed
    }

    /* ============ Constants ============== */
    /**
     * @dev Represents the scaling factor used in calculations
     */
    uint256 private constant PRECISION = 1e12;
    /**
     * @dev Represents the category LOCK STAKING in the LOCKON vesting
     */
    uint256 private constant LOCK_STAKING_VESTING_CATEGORY_ID = 0;

    /* ============ State Variables ============ */
    /**
     * @dev Address of the validator
     */
    address public validatorAddress;
    /**
     * @dev Address to receive penalty fee
     */
    address public feeReceiver;
    /**
     * @dev Address of LOCKON vesting contract
     */
    address public lockonVesting;
    /**
     * @dev Total number of tokens that has been locked into contract
     */
    uint256 public totalLockedAmount;
    /**
     * @dev Total number of LOCK scoreTotal number of LOCK score
     */
    uint256 public totalLockScore;
    /**
     * @dev Accumulated reward per score, times 1e12
     */
    uint256 public rewardPerScore;
    /**
     * @dev Timestamp on which staking process start
     */
    uint256 public startTimestamp;
    /**
     * @dev Timestamp on which LOCK token is released
     */
    uint256 public lockTokenReleasedTimestamp;
    /**
     * @dev Last block timestamp that reward distribution occurs
     */
    uint256 public lastRewardTimestamp;
    /**
     * @dev Current amount of reward used to pay for user staking's reward
     */
    uint256 public currentRewardAmount;
    /**
     * @dev Divider for the basic rate
     */
    uint256 public basicRateDivider;
    /**
     * @dev Bonus rate per second combine with current reward amount to get back reward token per second
     */
    uint256 public bonusRatePerSecond;
    /**
     * @dev Track the status of each requestId
     */
    mapping(string => bool) public isRequestIdProcessed;
    /**
     * @dev Mapping of user wallet address to UserInfo struct, which stores user staking information
     */
    mapping(address => UserInfo) public userInfo;
    /**
     * @dev Interface of the LOCK token contract
     */
    IERC20 public lockToken;
    /**
     * @dev Minimum lock duration
     */
    uint256 public minimumLockDuration;
    /**
     * @dev Penalty rate for early withdrawal
     */
    uint256 public penaltyRate;
    /**
     * @dev Reserved storage space to allow for layout changes in the future.
     */
    uint256[50] private __gap;

    /* ============ Events ============ */

    /**
     * Emitted when an user perform action on LOCK Staking
     *
     * @param sender Address of the function executor
     * @param rewardPerScore Accumulated reward per score
     * @param currentRewardAmount Current amount of reward used to pay for user staking's reward
     * @param lastRewardTimestamp Last block timestamp that reward distribution occurs
     */
    event PoolDataUpdated(
        address indexed sender, uint256 rewardPerScore, uint256 currentRewardAmount, uint256 lastRewardTimestamp
    );

    /**
     * Emitted when an user deposits LOCK Token
     *
     * @param sender Address of the function executor
     * @param lockedAmount Amount of LOCK Tokens being locked
     * @param lockDuration Duration of the lock
     * @param lastBasicRate Last recorded basic rate associated with the user's lock
     * @param rewardDebt User's accumulated reward debt at the time of the lock
     * @param lockEndTimestamp Timestamp representing the end of the lock duration
     */
    event LockTokenAdded(
        address indexed sender,
        uint256 lockedAmount,
        uint256 lockDuration,
        uint256 lastBasicRate,
        uint256 rewardDebt,
        uint256 lockEndTimestamp
    );

    /**
     * Emitted when an user extends the lock duration
     *
     * @param sender Address of the function executor
     * @param lockDuration New duration of the lock
     * @param lastBasicRate Last recorded basic rate associated with the user's lock
     * @param rewardDebt User's accumulated reward debt at the time user extends lock duration
     * @param lockEndTimestamp Timestamp representing the new end of the lock duration
     */
    event ExtendLockDuration(
        address indexed sender,
        uint256 lockDuration,
        uint256 lastBasicRate,
        uint256 rewardDebt,
        uint256 lockEndTimestamp
    );

    /**
     * Emitted when an user withdraws LOCK Tokens
     *
     * @param sender Address of the function executor
     * @param withdrawAmount Amount of LOCK Tokens being withdrawn
     * @param penaltyFee Penalty fee deducted from the withdrawal, if applicable
     * @param rewardDebt User's accumulated reward debt at the time user withdraws LOCK token
     */
    event WithdrawLockToken(address indexed sender, uint256 withdrawAmount, uint256 penaltyFee, uint256 rewardDebt);

    /**
     * @dev Emitted when an user claims their rewards
     *
     * @param sender Address of the function executor
     * @param requestId Id of the request generated by user
     * @param lockStakingReward Amount of LOCK staking rewards claimed by the user
     * @param commissionSharingReward The commission sharing reward sent from user
     * @param rewardDebt User's accumulated reward debt at the time of the claim
     */
    event ClaimLockStakingReward(
        address indexed sender,
        string requestId,
        uint256 lockStakingReward,
        uint256 commissionSharingReward,
        uint256 rewardDebt
    );

    /**
     * @dev Emitted when LOCK score of an user change
     *
     * @param user Address of the user
     * @param lockedScore User new LOCK score
     */
    event UserLockScoreChanged(address indexed user, uint256 lockedScore);

    /**
     * Emitted when the LOCKON Vesting address is updated
     *
     * @param sender Address of the function executor
     * @param lockonVesting New LOCKON Vesting address
     * @param timestamp Timestamp at which the address is updated
     */
    event LockonVestingUpdated(address indexed sender, address lockonVesting, uint256 timestamp);

    /**
     * Emitted when the fee receiver is updated
     *
     * @param sender Address of the function executor
     * @param feeReceiver New fee receiver address
     * @param timestamp Timestamp at which the address is updated
     */
    event FeeReceiverUpdated(address indexed sender, address feeReceiver, uint256 timestamp);

    /**
     * Emitted when the basic rate divider is updated
     *
     * @param sender Address of the function executor
     * @param basicRateDivider New Value for basic rate divider
     * @param currentRewardAmount New value for current reward amount
     * @param rewardPerScore New value for reward per score
     * @param lastRewardTimestamp New value for last reward timestamp
     * @param timestamp Timestamp at which the address is updated
     */
    event BasicRateDividerUpdated(
        address indexed sender,
        uint256 basicRateDivider,
        uint256 currentRewardAmount,
        uint256 rewardPerScore,
        uint256 lastRewardTimestamp,
        uint256 timestamp
    );

    /**
     * Emitted when the bonus rate per second is updated
     *
     * @param sender Address of the function executor
     * @param bonusRatePerSecond New value for bonus rate per second
     * @param currentRewardAmount New value for current reward amount
     * @param rewardPerScore New value for reward per score
     * @param lastRewardTimestamp New value for last reward timestamp
     * @param timestamp Timestamp at which the address is updated
     */
    event BonusRatePerSecondUpdated(
        address indexed sender,
        uint256 bonusRatePerSecond,
        uint256 currentRewardAmount,
        uint256 rewardPerScore,
        uint256 lastRewardTimestamp,
        uint256 timestamp
    );

    /**
     * Emitted when the minimum lock duration is updated
     *
     * @param sender Address of the function executor
     * @param minimumLockDuration New value for minimum lock duration
     * @param timestamp Timestamp at which the address is updated
     */
    event MinimumLockDurationUpdated(address indexed sender, uint256 minimumLockDuration, uint256 timestamp);

    /**
     * Emitted when the penalty rate is updated
     *
     * @param sender Address of the function executor
     * @param penaltyRate New value for penalty rate
     * @param timestamp Timestamp at which the address is updated
     */
    event PenaltyRateUpdated(address indexed sender, uint256 penaltyRate, uint256 timestamp);

    /**
     * Emitted when the validator address is updated
     *
     * @param sender Address of the function executor
     * @param validator New Validator address
     * @param timestamp Timestamp at which the address is updated
     */
    event ValidatorAddressUpdated(address indexed sender, address validator, uint256 timestamp);

    /**
     * Emitted when a user cancels a staking reward claim order
     *
     * @param sender Address of the function executor
     * @param requestId Identifier for the staking reward claim order being cancelled
     */
    event ClaimOrderCancel(address indexed sender, string requestId);

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
     * Initializes the LOCK Staking contract
     *
     * @param _owner      Address of the owner of this contract
     * @param _validator Address of the validator of this contract
     * @param _lockonVesting Address of the LOCKON Vesting contract
     * @param _feeReceiver      Address of the penalty fee receiver
     * @param _lockToken  Address of the LOCK Token
     * @param _startTimestamp  Timestamp on which staking process start
     * @param _currentRewardAmount  Total amount of reward used to pay for user staking's reward
     * @param _basicRateDivider  Divider for the basic rate
     * @param _bonusRatePerSecond  Basic rate for bonus reward per second multiplier
     */
    function initialize(
        address _owner,
        address _validator,
        address _lockonVesting,
        address _feeReceiver,
        address _lockToken,
        uint256 _startTimestamp,
        uint256 _currentRewardAmount,
        uint256 _basicRateDivider,
        uint256 _bonusRatePerSecond
    ) external initializer {
        require(_owner != address(0), "LOCK Staking: owner is the zero address");
        require(_validator != address(0), "LOCK Staking: validator is the zero address");
        require(_lockonVesting != address(0), "LOCK Staking: lockonVesting is the zero address");
        require(_feeReceiver != address(0), "LOCK Staking: feeReceiver is the zero address");
        require(_lockToken != address(0), "LOCK Staking: lockToken is the zero address");
        require(_bonusRatePerSecond != 0, "LOCK Staking: Bonus rate per second must be greater than 0");
        // Initialize the contract and set the owner
        // This function should be called only once during deployment
        __UUPSUpgradeable_init();
        __Ownable_init(_owner);
        __Pausable_init();
        EIP712Upgradeable.__EIP712_init("LOCK_STAKING", "1");
        __ReentrancyGuard_init();
        validatorAddress = _validator;
        lockonVesting = _lockonVesting;
        feeReceiver = _feeReceiver;
        lockToken = IERC20(_lockToken);
        // Set staking start timestamp
        startTimestamp = _startTimestamp;
        // Set last reward block equal to the time staking start
        lastRewardTimestamp = _startTimestamp;
        // Set total number of reward
        currentRewardAmount = _currentRewardAmount;
        basicRateDivider = _basicRateDivider;
        bonusRatePerSecond = _bonusRatePerSecond;
        // Set the deployed contract time as the time that LOCK token get released
        lockTokenReleasedTimestamp = block.timestamp;
        // Set penalty rate currently fixed at 30%
        penaltyRate = 300_000_000_000;
        minimumLockDuration = 100 days;
    }

    /* ============ View Functions ============ */

    /**
     * @dev Calculates and returns the basic rate based on the number of seconds that have passed since the LOCK
     * token was released. The rate is computed using a formula that times with 1e12 for decimals part
     */
    function basicRate() public view returns (uint256) {
        uint256 secondsPassed = (block.timestamp - lockTokenReleasedTimestamp);
        return PRECISION + (secondsPassed * basicRateDivider);
    }

    /**
     * @dev Calculates and returns the rate multiplier based on the specified lock duration
     * @param _lockDuration The duration for which the tokens are locked, represented in seconds
     */
    function durationRate(uint256 _lockDuration) public pure returns (uint256) {
        if (_lockDuration >= 1000 days) {
            return 16e12;
        }
        if (_lockDuration >= 600 days) {
            return 8e12;
        }
        if (_lockDuration >= 300 days) {
            return 3.5e12;
        }
        if (_lockDuration >= 100 days) {
            return 1e12;
        }
        return 0;
    }

    /**
     * @dev Calculates and returns the reward token per second amount
     */
    function rewardTokenPerSecond() public view returns (uint256) {
        return (currentRewardAmount * bonusRatePerSecond) / PRECISION;
    }

    /**
     * @dev Calculates and returns a reward multiplier for a specified time range (`_from` to `_to`)
     * The multiplier is determined by invoking the `rewardTokenPerSecond` function and multiplying it by
     * the time duration between `_from` and `_to`
     * @param _from The starting timestamp of the time range
     * @param _to The ending timestamp of the time range
     */
    function getRewardMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        uint256 multiplier = rewardTokenPerSecond();
        uint256 rewardDistributed = (_to - _from) * multiplier;
        if (rewardDistributed < currentRewardAmount) {
            return rewardDistributed;
        }
        return currentRewardAmount;
    }

    /**
     * @dev Calculates and returns the lock score of the user
     * @param _lockAmount   Amount of LOCK Token to stake
     * @param _lockDuration   Duration of the lock
     */
    function getUserLockScore(uint256 _lockAmount, uint256 _lockDuration) public view returns (uint256) {
        uint256 now_ = block.timestamp;
        if (_lockDuration < minimumLockDuration || now_ < startTimestamp) return 0;
        UserInfo storage _currentUserInfo = userInfo[msg.sender];
        uint256 userLockAmount = _currentUserInfo.lockedAmount;
        userLockAmount += _lockAmount;
        (, uint256 newLockDuration) = _calculateLockTimestamp(_currentUserInfo.lockEndTimestamp, _lockDuration, now_);
        return (userLockAmount * basicRate() * durationRate(newLockDuration)) / PRECISION / PRECISION;
    }

    /**
     * @dev Calculates and returns the pending reward for a given user based on their deposited amount,
     * the current reward rate per LOCK score, the cumulative pending reward and the difference in block
     * timestamps between the last reward calculation and the current block
     * Whenever an user add, extend or withdraws LOCK tokens . Here's what happens:
     *   1. The pool's `rewardPerScore` gets updated
     *   2. User receives the pending reward amount that can be sent to his/her address
     * @param _user User address
     */
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 _rewardPerScore = rewardPerScore;
        if (block.timestamp > lastRewardTimestamp && totalLockScore != 0) {
            // Calculate the reward multiplier based on the difference in block timestamps
            uint256 lockReward = getRewardMultiplier(lastRewardTimestamp, block.timestamp);
            // Update the reward rate per LOCK score
            _rewardPerScore = _rewardPerScore + ((lockReward * PRECISION) / totalLockScore);
        }
        // Calculate and return the pending reward for the user
        return user.cumulativePendingReward + ((user.lockScore * _rewardPerScore) / PRECISION) - user.rewardDebt;
    }

    /* ============ Private Functions ============ */

    /**
     * @dev Updates the pool by calculating and distributing rewards to stakers based on the difference in block
     * timestamps between the last reward calculation and the current block. The function adjusts the reward rate
     * per LOCK score.
     * The function also updates the last reward block and deducts the distributed rewards from the current reward
     * amount.
     */
    function _updatePool() private {
        if (block.timestamp <= startTimestamp) {
            return;
        }
        if (totalLockScore == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }
        // Calculate the reward multiplier based on the difference in block timestamps
        uint256 lockReward = getRewardMultiplier(lastRewardTimestamp, block.timestamp);
        if (lockReward == 0) {
            return;
        }
        // Update state data
        rewardPerScore = rewardPerScore + ((lockReward * PRECISION) / totalLockScore);
        currentRewardAmount = currentRewardAmount - lockReward;
        lastRewardTimestamp = block.timestamp;
        emit PoolDataUpdated(msg.sender, rewardPerScore, currentRewardAmount, lastRewardTimestamp);
    }

    /* ============ External Functions ============ */

    /**
     * Deposit LOCK Token for staking
     *
     * @param _lockAmount   Amount of LOCK Token to stake
     * @param _lockDuration   Duration of the lock
     */
    function addLockToken(uint256 _lockAmount, uint256 _lockDuration) external whenNotPaused nonReentrant {
        uint256 now_ = block.timestamp;
        require(_lockAmount != 0, "LOCK Staking: Locked amount must be greater than 0");
        require(_lockDuration >= minimumLockDuration, "LOCK Staking: Minimum lock duration does not meet");
        require(now_ >= startTimestamp, "LOCK Staking: Staking not start");

        _updatePool();

        UserInfo storage _currentUserInfo = userInfo[msg.sender];

        // If previous locked, calculated received amount
        if (_currentUserInfo.lockScore > 0) {
            uint256 pending = ((_currentUserInfo.lockScore * rewardPerScore) / PRECISION) - _currentUserInfo.rewardDebt;
            if (pending > 0) {
                _currentUserInfo.cumulativePendingReward += pending;
            }
            totalLockScore -= _currentUserInfo.lockScore;
        }

        (uint256 newLockEndTimestamp, uint256 newLockDuration) =
            _calculateLockTimestamp(_currentUserInfo.lockEndTimestamp, _lockDuration, now_);
        uint256 _currentBasicRate = basicRate();

        // Update user info
        _currentUserInfo.lockedAmount += _lockAmount;
        _currentUserInfo.lastBasicRate = _currentBasicRate;
        // Calculate user LOCK score with new lock duration
        uint256 userLockScore =
            (_currentUserInfo.lockedAmount * _currentBasicRate * durationRate(newLockDuration)) / PRECISION / PRECISION;
        _currentUserInfo.lockScore = userLockScore;
        _currentUserInfo.rewardDebt = (userLockScore * rewardPerScore) / PRECISION;
        _currentUserInfo.lockEndTimestamp = newLockEndTimestamp;
        _currentUserInfo.lockDuration = newLockDuration;

        // Update state data
        totalLockedAmount += _lockAmount;
        totalLockScore += userLockScore;

        // Transfer the locked tokens from the user to this contract
        lockToken.safeTransferFrom(msg.sender, address(this), _lockAmount);

        emit UserLockScoreChanged(msg.sender, userLockScore);
        emit LockTokenAdded(
            msg.sender,
            _lockAmount,
            newLockDuration,
            _currentBasicRate,
            (userLockScore * rewardPerScore) / PRECISION,
            newLockEndTimestamp
        );
    }

    /**
     * Allows an user to extend the lock duration of their staked LOCK Token
     *
     * Requirements:
     * - The user must have previously locked tokens
     * - The new lock duration must be greater than the current lock duration
     *
     * @param _lockDuration   New duration of the lock
     */
    function extendLockDuration(uint256 _lockDuration) external whenNotPaused {
        UserInfo storage _currentUserInfo = userInfo[msg.sender];
        require(_currentUserInfo.lockedAmount != 0, "LOCK Staking: Nothing to extend");
        require(_lockDuration >= minimumLockDuration, "LOCK Staking: Minimum lock duration does not meet");
        _updatePool();

        // Calculate previous reward amount
        uint256 pending = ((_currentUserInfo.lockScore * rewardPerScore) / PRECISION) - _currentUserInfo.rewardDebt;
        if (pending != 0) {
            _currentUserInfo.cumulativePendingReward += pending;
        }

        uint256 now_ = block.timestamp;
        (uint256 newLockEndTimestamp, uint256 newLockDuration) =
            _calculateLockTimestamp(_currentUserInfo.lockEndTimestamp, _lockDuration, now_);
        uint256 _currentBasicRate = basicRate();

        // Update user info
        _currentUserInfo.lastBasicRate = _currentBasicRate;
        // Calculate user LOCK score with new lock duration
        uint256 userLockScore =
            (_currentUserInfo.lockedAmount * _currentBasicRate * durationRate(newLockDuration)) / PRECISION / PRECISION;
        // Update state data
        totalLockScore = totalLockScore - _currentUserInfo.lockScore + userLockScore;
        _currentUserInfo.lockScore = userLockScore;
        _currentUserInfo.rewardDebt = (userLockScore * rewardPerScore) / PRECISION;
        _currentUserInfo.lockEndTimestamp = newLockEndTimestamp;
        _currentUserInfo.lockDuration = newLockDuration;

        emit UserLockScoreChanged(msg.sender, userLockScore);
        emit ExtendLockDuration(
            msg.sender,
            newLockDuration,
            _currentBasicRate,
            (userLockScore * rewardPerScore) / PRECISION,
            newLockEndTimestamp
        );
    }

    /**
     * @dev Allows an user to withdraw their staked LOCK Tokens. If the user withdraws early,
     * a penalty fee may be applied before transferring the remaining tokens.
     *
     * @param _amount The amount of LOCK Tokens to withdraw.
     */
    function withdrawLockToken(uint256 _amount) external whenNotPaused nonReentrant {
        UserInfo storage _currentUserInfo = userInfo[msg.sender];
        require(_currentUserInfo.lockedAmount != 0, "LOCK Staking: Nothing to withdraw");
        require(_amount != 0, "LOCK Staking: Withdraw amount must be greater than 0");
        require(_currentUserInfo.lockedAmount >= _amount, "LOCK Staking: Withdraw amount exceed available");

        _updatePool();

        // Calculate previous reward amount
        uint256 pending = ((_currentUserInfo.lockScore * rewardPerScore) / PRECISION) - _currentUserInfo.rewardDebt;
        if (pending != 0) {
            _currentUserInfo.cumulativePendingReward += pending;
        }

        // Calculate user LOCK score after withdraw
        uint256 userLockScore = (
            (_currentUserInfo.lockedAmount - _amount) * _currentUserInfo.lastBasicRate
                * durationRate(_currentUserInfo.lockDuration)
        ) / PRECISION / PRECISION;

        uint256 _penaltyFee;
        // Check if the user is withdrawing early to apply a penalty fee
        if (block.timestamp < _currentUserInfo.lockEndTimestamp) {
            _penaltyFee = (_amount * penaltyRate) / PRECISION;
        }
        // Deduct total lock score when withdraw LOCK tokens
        totalLockScore = totalLockScore - _currentUserInfo.lockScore + userLockScore;

        // Update user info
        _currentUserInfo.lockedAmount = _currentUserInfo.lockedAmount - _amount;
        _currentUserInfo.lockScore = userLockScore;
        _currentUserInfo.rewardDebt = (userLockScore * rewardPerScore) / PRECISION;

        // Update lock timestamp when all tokens are withdrawn
        if (_currentUserInfo.lockedAmount == 0 && _currentUserInfo.lockEndTimestamp > block.timestamp) {
            _currentUserInfo.lockEndTimestamp = block.timestamp;
        }

        // Update state data
        totalLockedAmount -= _amount;

        // Transfer the penalty fee to the validator's address
        lockToken.safeTransfer(feeReceiver, _penaltyFee);
        // Transfer the remaining locked tokens to the user
        lockToken.safeTransfer(msg.sender, _amount - _penaltyFee);

        emit UserLockScoreChanged(msg.sender, userLockScore);
        emit WithdrawLockToken(msg.sender, _amount, _penaltyFee, (userLockScore * rewardPerScore) / PRECISION);
    }

    /**
     * @dev Allows an user to claim their staking reward
     * @param _requestId The Id of the request from users
     * @param _commissionSharingReward The commission sharing reward sent from user
     * @param _signature The signature to validate the claim
     */
    function claimPendingReward(string calldata _requestId, uint256 _commissionSharingReward, bytes memory _signature)
        external
        whenNotPaused
        nonReentrant
    {
        UserInfo storage _currentUserInfo = userInfo[msg.sender];
        require(
            _currentUserInfo.lockScore != 0 || _currentUserInfo.cumulativePendingReward != 0
                || _commissionSharingReward != 0,
            "LOCK Staking: Nothing to claim"
        );
        require(!isRequestIdProcessed[_requestId], "LOCK Staking: Request already processed");
        // Verify the signature to ensure the validity of the distribution
        require(
            getSignerForRequest(_requestId, msg.sender, _commissionSharingReward, _signature) == validatorAddress,
            "LOCK Staking: Invalid signature"
        );
        _updatePool();
        uint256 lockStakingReward = _currentUserInfo.cumulativePendingReward
            + ((_currentUserInfo.lockScore * rewardPerScore) / PRECISION) - _currentUserInfo.rewardDebt;
        uint256 totalCumulativeReward = lockStakingReward + _commissionSharingReward;
        if (totalCumulativeReward != 0) {
            // Approve the LOCKON vesting contract to spend the cumulative reward token
            uint256 currentAllowance = lockToken.allowance(address(this), lockonVesting);
            if (currentAllowance < totalCumulativeReward) {
                lockToken.safeIncreaseAllowance(lockonVesting, totalCumulativeReward - currentAllowance);
            }
            ILockonVesting(lockonVesting).deposit(msg.sender, totalCumulativeReward, LOCK_STAKING_VESTING_CATEGORY_ID);
            _currentUserInfo.cumulativePendingReward = 0;
        }
        // Mark the requestId as processed to prevent duplicate claim
        isRequestIdProcessed[_requestId] = true;
        _currentUserInfo.rewardDebt = (_currentUserInfo.lockScore * rewardPerScore) / PRECISION;

        emit ClaimLockStakingReward(
            msg.sender, _requestId, lockStakingReward, _commissionSharingReward, _currentUserInfo.rewardDebt
        );
    }

    /**
     * @dev Allows a user to cancel a staking reward claim order for a specific pool
     *
     * @param _requestId An ID for the staking reward claim order
     * @param _claimAmount The amount of reward tokens in the claim order
     * @param _signature The signature to validate the cancellation
     */
    function cancelClaimOrder(string calldata _requestId, uint256 _claimAmount, bytes memory _signature)
        external
        whenNotPaused
    {
        UserInfo storage user = userInfo[msg.sender];
        require(user.lockEndTimestamp != 0, "LOCK Staking: User hasn't staked any token yet");

        require(!isRequestIdProcessed[_requestId], "LOCK Staking: Request already processed");

        // Verify the signature to ensure the validity of the cancellation
        require(
            getSignerForRequest(_requestId, msg.sender, _claimAmount, _signature) == validatorAddress,
            "LOCK Staking: Invalid signature"
        );
        // Mark the order as cancelled
        isRequestIdProcessed[_requestId] = true;

        emit ClaimOrderCancel(msg.sender, _requestId);
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
        require(_lockonVesting != address(0), "LOCK Staking: Zero address not allowed");
        lockonVesting = _lockonVesting;
        emit LockonVestingUpdated(msg.sender, lockonVesting, block.timestamp);
    }

    /**
     * @dev Set the validator address responsible for reward distribution
     * @param _validatorAddress  Address of the validator
     */
    function setValidatorAddress(address _validatorAddress) external onlyOwner {
        require(_validatorAddress != address(0), "LOCK Staking: Zero address not allowed");
        validatorAddress = _validatorAddress;
        emit ValidatorAddressUpdated(msg.sender, validatorAddress, block.timestamp);
    }

    /**
     * @dev Set the address that will receive the penalty fee for early withdrawal
     * @param _feeReceiver  Address of the fee receiver
     */
    function setFeeReceiver(address _feeReceiver) external onlyOwner {
        require(_feeReceiver != address(0), "LOCK Staking: Zero address not allowed");
        feeReceiver = _feeReceiver;
        emit FeeReceiverUpdated(msg.sender, feeReceiver, block.timestamp);
    }

    /**
     * @dev Allows the owner to set the basic rate divider, influencing the basic rate calculation
     *
     * @param _basicRateDivider The new value for the basic rate divider
     */
    function setBasicRateDivider(uint256 _basicRateDivider) external onlyOwner {
        _updatePool();
        basicRateDivider = _basicRateDivider;
        emit BasicRateDividerUpdated(
            msg.sender, basicRateDivider, currentRewardAmount, rewardPerScore, lastRewardTimestamp, block.timestamp
        );
    }

    /**
     * @dev Allows the owner to set the bonus rate per second, influencing the reward token per second calculation
     *
     * @param _bonusRatePerSecond The new value for the second bonus rate
     */
    function setBonusRatePerSecond(uint256 _bonusRatePerSecond) external onlyOwner {
        require(_bonusRatePerSecond != 0, "LOCK Staking: Bonus rate per second must be greater than 0");
        _updatePool();
        bonusRatePerSecond = _bonusRatePerSecond;
        emit BonusRatePerSecondUpdated(
            msg.sender, bonusRatePerSecond, currentRewardAmount, rewardPerScore, lastRewardTimestamp, block.timestamp
        );
    }

    /**
     * @dev Allows the owner to set the minimum lock duration
     *
     * @param _minimumLockDuration The new value for the minimum lock duration
     */
    function setMinimumLockDuration(uint256 _minimumLockDuration) external onlyOwner {
        minimumLockDuration = _minimumLockDuration;
        emit MinimumLockDurationUpdated(msg.sender, minimumLockDuration, block.timestamp);
    }

    /**
     * @dev Allows the owner to set the penalty rate
     *
     * @param _penaltyRate The new value for the penalty rate
     */
    function setPenaltyRate(uint256 _penaltyRate) external onlyOwner {
        penaltyRate = _penaltyRate;
        emit PenaltyRateUpdated(msg.sender, penaltyRate, block.timestamp);
    }

    /**
     * @dev Allows the owner to add LOCK tokens to contract LOCK staking
     *
     * @param _lockAmount The LOCK token amount to be added
     */
    function allocateLockToken(uint256 _lockAmount) external onlyOwner nonReentrant {
        lockToken.safeTransferFrom(msg.sender, address(this), _lockAmount);
        emit LockTokenAllocated(msg.sender, _lockAmount);
    }

    /**
     * @dev Allows the owner to withdraw LOCK tokens from contract LOCK staking
     *
     * @param _lockAmount The LOCK token amount to be withdrawn
     */
    function deallocateLockToken(uint256 _lockAmount) external onlyOwner nonReentrant {
        lockToken.safeTransfer(msg.sender, _lockAmount);
        emit LockTokenDeallocated(msg.sender, _lockAmount);
    }

    /**
     * @dev Calculate new lock duration
     *
     * @param currentLockEnd The current lock duration
     * @param newDuration The new lock token duration
     * @param now_ The current block timestamp
     */
    function _calculateLockTimestamp(uint256 currentLockEnd, uint256 newDuration, uint256 now_)
        private
        pure
        returns (uint256, uint256)
    {
        if (currentLockEnd > now_) {
            uint256 durationLeft = currentLockEnd - now_;
            require(newDuration >= durationLeft, "LOCK Staking: Invalid lock duration");
        }
        return (now_ + newDuration, newDuration);
    }

    /* ============ Verify signature Functions ============ */

    /**
     * @dev Get signer from data and signature of the reward claim request
     *
     * @param _requestId An ID for the reward claim request
     * @param _rewardAmount The amount of reward tokens to be claimed
     * @param _signature The signature to validate the reward claim request
     */
    function getSignerForRequest(
        string calldata _requestId,
        address _beneficiary,
        uint256 _rewardAmount,
        bytes memory _signature
    ) public view returns (address) {
        ClaimRequest memory claimRequest = ClaimRequest(_requestId, _beneficiary, _rewardAmount);
        address signer = _verifyClaimRequest(claimRequest, _signature);
        return signer;
    }

    /**
     * @dev Return domain separator for LOCK Staking
     */
    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @dev Verify the reward claim request with signature
     *
     * @param _claimRequest An ID for the reward claim request
     * @param _signature The signature to validate the claim request
     */
    function _verifyClaimRequest(ClaimRequest memory _claimRequest, bytes memory _signature)
        private
        view
        returns (address)
    {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256("ClaimRequest(string requestId,address beneficiary,uint256 rewardAmount)"),
                    keccak256(bytes(_claimRequest.requestId)),
                    _claimRequest.beneficiary,
                    _claimRequest.rewardAmount
                )
            )
        );
        return ECDSA.recover(digest, _signature);
    }

    /**
     * @dev Override function from UUPS contract for upgrade authorize
     * @param newImplementation  Address of the new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
