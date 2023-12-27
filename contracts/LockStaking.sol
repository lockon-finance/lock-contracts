//SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ILockonVesting.sol";

/**
 * @title Lock Staking contract
 * @author LOCKON protocol
 * @dev Allows users to stake LOCK Token and claim rewards
 *
 */
contract LockStaking is Initializable, OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable {
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
    }
    // The staking logic is heavily inspired by SushiSwap’s MasterChef contract,
    // here is an explanation of the `rewardDebt` parameter:
    // Basically, any point in time, the amount of reward token
    // entitled to a user but is pending to be distributed is:
    //
    //    pending reward = (user.score * rewardPerScore) - user.rewardDebt
    //
    // Whenever a user add, extend or withdraws Lock tokens to contract. Here's what happens:
    //   1. The contract's `rewardPerScore` (and `lastRewardTimestamp`) gets updated.
    //   2. User receives the pending reward, this amount will be immediately
    //       transferred to the vesting contract to create a vesting information.
    //   3. User's `lockedAmount` gets updated.
    //   4. User's `rewardDebt` gets updated.

    /* ============ Constants ============== */
    // Represents the scaling factor used in calculations
    uint256 public constant PRECISION = 1e12;

    /* ============ State Variables ============ */
    // Address to receive penalty fee
    address public feeReceiver;
    // Address of LOCKON vesting contract
    address public lockonVesting;
    // Total number of tokens that has been locked into contract
    uint256 public totalLockedAmount;
    // Total number of LOCK score
    uint256 public totalLockScore;
    // Accumulated reward per score, times 1e12
    uint256 public rewardPerScore;
    // Timestamp on which staking process start
    uint256 public startTimestamp;
    // Timestamp on which LOCK token is released
    uint256 public lockTokenReleasedTimestamp;
    // Last block timestamp that reward distribution occurs
    uint256 public lastRewardTimestamp;
    // Current amount of reward used to pay for user staking's reward
    uint256 public currentRewardAmount;
    // Divider for the basic rate
    uint256 public basicRateDivider;
    // Bonus rate per second combine with current reward amount to get back reward token per second
    uint256 public bonusRatePerSecond;
    // Mapping of user wallet address to UserInfo struct, which stores user staking information
    mapping(address => UserInfo) public userInfo;
    // Interface of the LOCK token contract
    IERC20 public lockToken;
    // Minimum lock duration
    uint256 public minimumLockDuration;
    // Penalty rate for early withdrawal
    uint256 public penaltyRate;

    /* ============ Events ============ */

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
     * @param claimedAmount Amount of rewards claimed by the user
     * @param rewardDebt User's accumulated reward debt at the time of the claim
     */
    event ClaimLockStakingReward(address indexed sender, uint256 claimedAmount, uint256 rewardDebt);

    /**
     * @dev Emitted when LOCK score of an user change
     *
     * @param user Address of the user
     * @param lockedScore User new LOCK score
     */
    event UserLockScoreChanged(address indexed user, uint256 lockedScore);

    /**
     * Initializes the Lock Staking contract
     *
     * @param _owner      Address of the owner of this contract
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
        address _lockonVesting,
        address _feeReceiver,
        address _lockToken,
        uint256 _startTimestamp,
        uint256 _currentRewardAmount,
        uint256 _basicRateDivider,
        uint256 _bonusRatePerSecond
    ) public initializer {
        // Initialize the contract and set the owner
        // This function should be called only once during deployment
        __Ownable_init_unchained(_owner);

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

        // TODO: Remove this and add approve when claim
        // Approve the LOCKON vesting contract to spend the reward token
        lockToken.approve(lockonVesting, type(uint256).max);
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

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
     * @dev Calculates and returns the pending reward for a given user based on their deposited amount,
     * the current reward rate per LOCK score, and the difference in block timestamps between the last
     * reward calculation and the current block
     * Whenever an user add, extend or withdraws LOCK tokens . Here's what happens:
     *   1. The pool's `rewardPerScore`, `currentRewardAmount` (and `lastRewardTimestamp`) gets updated
     *   2. User receives the pending reward sent to his/her address
     *   3. User's `rewardDebt` gets updated
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
        return ((user.lockScore * _rewardPerScore) / PRECISION) - user.rewardDebt;
    }

    /* ============ Public Functions ============ */

    /**
     * @dev Updates the pool by calculating and distributing rewards to stakers based on the difference in block
     * timestamps between the last reward calculation and the current block. The function adjusts the reward rate
     * per LOCK score and ensures that the reward distribution does not exceed the available reward supply.
     * The function also updates the last reward block and deducts the distributed rewards from the current reward
     * amount.
     */
    function updatePool() public {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }
        if (totalLockScore == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }
        uint256 rewardSupply = lockToken.balanceOf(address(this));
        // Calculate the reward multiplier based on the difference in block timestamps
        uint256 lockReward = getRewardMultiplier(lastRewardTimestamp, block.timestamp);
        // Ensure that the reward supply is sufficient for the calculated rewards
        require(rewardSupply >= lockReward, "Lock Staking: Reward distributed exceed supply");

        // Update state data
        rewardPerScore = rewardPerScore + ((lockReward * PRECISION) / totalLockScore);
        currentRewardAmount = currentRewardAmount - lockReward;
        lastRewardTimestamp = block.timestamp;
    }

    /* ============ External Functions ============ */

    /**
     * Deposit LOCK Token for staking
     *
     * @param _lockAmount   Amount of LOCK Token to stake
     * @param _lockDuration   Duration of the lock
     */
    function addLockToken(uint256 _lockAmount, uint256 _lockDuration) external whenNotPaused {
        uint256 now_ = block.timestamp;
        require(_lockAmount > 0, "Lock Staking: Locked amount must be greater than 0");
        require(_lockDuration >= minimumLockDuration, "Lock Staking: Minimum lock duration does not meet");
        require(now_ >= startTimestamp, "Lock Staking: Staking not start");

        updatePool();

        UserInfo storage _currentUserInfo = userInfo[msg.sender];

        // If previous locked, calculated received amount
        if (_currentUserInfo.lockScore > 0) {
            uint256 pending = ((_currentUserInfo.lockScore * rewardPerScore) / PRECISION) - _currentUserInfo.rewardDebt;
            if (pending > 0) {
                // TODO: Remove auto add vesting
                ILockonVesting(lockonVesting).addVestingWallet(
                    msg.sender, pending, ILockonVesting.VestingTag.LOCK_STAKING_ADD
                );
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
        require(_currentUserInfo.lockedAmount > 0, "Lock Staking: Nothing to extend");
        require(_lockDuration >= minimumLockDuration, "Lock Staking: Minimum lock duration does not meet");
        updatePool();

        // Calculate previous reward amount
        uint256 pending = ((_currentUserInfo.lockScore * rewardPerScore) / PRECISION) - _currentUserInfo.rewardDebt;
        if (pending > 0) {
            // TODO: Remove auto add vesting
            ILockonVesting(lockonVesting).addVestingWallet(
                msg.sender, pending, ILockonVesting.VestingTag.LOCK_STAKING_EXTEND
            );
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
    function withdrawLockToken(uint256 _amount) external whenNotPaused {
        UserInfo storage _currentUserInfo = userInfo[msg.sender];
        require(_currentUserInfo.lockedAmount > 0, "Lock Staking: Nothing to withdraw");
        require(_amount > 0, "Lock Staking: Withdraw amount must be greater than 0");
        require(_currentUserInfo.lockedAmount >= _amount, "Lock Staking: Withdraw amount exceed available");

        updatePool();

        // Calculate previous reward amount
        uint256 pending = ((_currentUserInfo.lockScore * rewardPerScore) / PRECISION) - _currentUserInfo.rewardDebt;
        if (pending > 0) {
            // TODO: Remove auto add vesting
            ILockonVesting(lockonVesting).addVestingWallet(
                msg.sender, pending, ILockonVesting.VestingTag.LOCK_STAKING_WITHDRAW
            );
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

        // Update state data
        totalLockedAmount -= _amount;

        // Transfer the penalty fee to the validator's address
        if (_penaltyFee != 0) lockToken.safeTransfer(feeReceiver, _penaltyFee);
        // Transfer the remaining locked tokens to the user
        lockToken.safeTransfer(msg.sender, _amount - _penaltyFee);

        emit UserLockScoreChanged(msg.sender, userLockScore);
        emit WithdrawLockToken(msg.sender, _amount, _penaltyFee, (userLockScore * rewardPerScore) / PRECISION);
    }

    /**
     * @dev Allows an user to claim their staking reward
     */
    function claimPendingReward() external whenNotPaused {
        UserInfo storage _currentUserInfo = userInfo[msg.sender];
        require(_currentUserInfo.lockScore > 0, "Lock Staking: Current score is zero");

        updatePool();

        uint256 pending = ((_currentUserInfo.lockScore * rewardPerScore) / PRECISION) - _currentUserInfo.rewardDebt;
        if (pending > 0) {
            lockToken.approve(lockonVesting, pending);
            ILockonVesting(lockonVesting).addVestingWallet(
                msg.sender, pending, ILockonVesting.VestingTag.LOCK_STAKING_CLAIM
            );
        }

        _currentUserInfo.rewardDebt = (_currentUserInfo.lockScore * rewardPerScore) / PRECISION;

        emit ClaimLockStakingReward(msg.sender, pending, (_currentUserInfo.lockScore * rewardPerScore) / PRECISION);
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
        require(_lockonVesting != address(0), "Lock Staking: Zero address not allowed");
        lockonVesting = _lockonVesting;
    }

    /**
     * @dev Set the address that will receive the penalty fee for early withdrawal
     * @param _feeReceiver  Address of the fee receiver
     */
    function setFeeReceiver(address _feeReceiver) external onlyOwner {
        require(_feeReceiver != address(0), "Lock Staking: Zero address not allowed");
        feeReceiver = _feeReceiver;
    }

    /**
     * @dev Allows the owner to set the basic rate divider, influencing the basic rate calculation
     *
     * @param _basicRateDivider The new value for the basic rate divider
     */
    function setBasicRateDivider(uint256 _basicRateDivider) external onlyOwner {
        basicRateDivider = _basicRateDivider;
    }

    /**
     * @dev Allows the owner to set the bonus rate per second, influencing the reward token per second calculation
     *
     * @param _bonusRatePerSecond The new value for the second bonus rate
     */
    function setBonusRatePerSecond(uint256 _bonusRatePerSecond) external onlyOwner {
        bonusRatePerSecond = _bonusRatePerSecond;
    }

    /**
     * @dev Allows the owner to set the minimum lock duration
     *
     * @param _minimumLockDuration The new value for the minimum lock duration
     */
    function setMinimumLockDuration(uint256 _minimumLockDuration) external onlyOwner {
        minimumLockDuration = _minimumLockDuration;
    }

    /**
     * @dev Allows the owner to set the penalty rate
     *
     * @param _penaltyRate The new value for the penalty rate
     */
    function setPenaltyRate(uint256 _penaltyRate) external onlyOwner {
        penaltyRate = _penaltyRate;
    }

    function _calculateLockTimestamp(uint256 currentLockEnd, uint256 newDuration, uint256 now_)
        internal
        pure
        returns (uint256, uint256)
    {
        if (currentLockEnd > now_) {
            uint256 durationLeft = currentLockEnd - now_;
            require(newDuration >= durationLeft, "Lock Staking: Invalid lock duration");
        }
        return (now_ + newDuration, newDuration);
    }

    /**
     * @dev Override function from UUPS contract for upgrade authorize
     * @param newImplementation  Address of the new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
