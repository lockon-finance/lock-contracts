//SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ILockToken} from "./interfaces/ILockToken.sol";

/**
 * @title LOCKON Vesting contract
 * @author LOCKON
 * @dev An ownable contract that can receive ERC20 LOCK tokens, and release these assets to the specified
 * wallet address, also referred to as "beneficiary", according to a vesting schedule.
 *
 * There are currently 4 vesting categories: LOCK STAKING, INDEX STAKING, AIRDROP and OTHER. Each user will
 * have up to 4 vesting wallets corresponding to these categories.
 *
 * Any assets transferred to this contract will follow the vesting schedule as if they were locked from
 * the beginning. Each time user deposit LOCK tokens to their vesting wallet, the vesting schedule will reset.
 *
 * NOTE:  Since the contract is {Ownable}, only wallet address that has ownership can create new vesting
 * schedule for new wallet (ownership can be transferred)
 *
 */
contract LockonVesting is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for ILockToken;

    /* ============ Constants ============== */
    /**
     * @dev Maximum number of vesting periods per user-category pair
     */
    uint256 private constant MAX_PARALLEL_VESTING = 50;

    /* ============ Vesting Struct ============ */

    struct VestingWallet {
        uint256 vestingAmount; // The total amount of tokens granted for vesting
        uint256 carriedOverClaimableAmount; // Claimable amount carried over from previous vesting period
        uint256 claimedAmount; // The amount of tokens already released from vesting based on current schedule
        uint256 startTime; // The starting time of the vesting period
    }

    enum DepositType {
        NewSlot,           // 0: New vesting slot created
        MaturedReuse,      // 1: Matured slot reused
        ActiveOverwrite    // 2: Active slot overwritten
    }

    /* ============ State Variables ============ */

    /**
     * @dev Mapping of vesting category id to its vesting schedule
     *
     * Ex: category id 0 represents category LOCK STAKING, has a vesting schedule of 100 days
     * => categoryId[0] = 100 days;
     */
    mapping(uint256 => uint256) public vestingCategories;
    /**
     * @dev Mapping of user address to VestingWallet array based on vesting category id
     * Each user-category pair can have up to MAX_PARALLEL_VESTING vesting periods
     * @notice Array order is not guaranteed - periods may be in any order due to removals during claim operations
     * Do not rely on array indices being stable or sorted by startTime
     */
    mapping(address => mapping(uint256 => VestingWallet[])) public userVestingWallets;
    /**
     * @dev Mapping that keeps track of whether each address is allowed to deposit to LOCKON Vesting contract
     */
    mapping(address => bool) public isAllowedDeposit;
    /**
     * @dev Mapping that keeps track of whether each address is banned from all activities in LOCKON Vesting
     * NOTE: Deprecated - Blacklist functionality has been migrated to LockToken contract
     */
    mapping(address => bool) private isBlacklistUser;
    /**
     * @dev List address allowed to receive to deposit to LOCKON Vesting contract
     */
    address[] public listAllowedDeposit;
    /**
     * @dev Mapping that keeps track each user address index in the list allowed deposit address
     */
    mapping(address => uint256) private allowedDepositOneBasedIndexes;
    /**
     * @dev List address banned from any activities in LOCKON Vesting, only owner can see this
     * NOTE: Deprecated - Blacklist functionality has been migrated to LockToken contract
     */
    address[] private blacklist;
    /**
     * @dev Mapping that keeps track each user address index in the blacklist
     * NOTE: Deprecated - Blacklist functionality has been migrated to LockToken contract
     */
    mapping(address => uint256) private blacklistOneBasedIndexes;
    /**
     * @dev Interface of the LOCK token contract
     */
    ILockToken public lockToken;
    /**
     * @dev Reserved storage space to allow for layout changes in the future.
     */
    uint256[50] private __gap;

    /* ============ Events ============ */

    /**
     * Emitted when a new vesting wallet is added
     *
     * @param sender Address of the function executor
     * @param user Address of the user who owns vesting
     * @param depositAmount Amount token deposited for vesting
     * @param vestingAmount Total granted amount for vesting
     * @param startTime Starting time of the new vesting
     * @param categoryId A category id associated with the vesting schedule
     * @param depositType Type of deposit (NewSlot/MaturedReuse/ActiveOverwrite)
     */
    event VestingDeposited(
        address indexed sender,
        address user,
        uint256 depositAmount,
        uint256 vestingAmount,
        uint256 startTime,
        uint256 categoryId,
        DepositType depositType
    );

    /**
     * Emitted when a user claims vested tokens
     *
     * @param sender Address of the function executor
     * @param categoryId A category id associated with the vesting schedule
     * @param claimedAmount Amount of tokens user claimed
     */
    event VestingClaimed(address indexed sender, uint256 categoryId, uint256 claimedAmount);

    /**
     * Emitted when an address is added or removed from list allowed deposit address
     *
     * @param sender Address of the function executor
     * @param userAddress address to be updated deposit permission
     * @param depositPermission status for checking if address can deposit to LOCKON Vesting
     * @param timestamp Timestamp at which the address is added or removed
     */
    event DepositPermissionStatusUpdated(
        address indexed sender, address userAddress, bool depositPermission, uint256 timestamp
    );

    /**
     * @dev Modifier that only owner and address that allowed to deposit can call certain functions
     */
    modifier onlyDepositGrantedOrOwner() {
        require(isAllowedDeposit[msg.sender] || msg.sender == owner(), "LOCKON Vesting: Forbidden");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * Initializes the vesting contract
     *
     * @param _owner      Address of the owner of this contract
     * @param _lockToken  Address of the ERC20 LOCK Token
     * @param _categoryIds The new category id list
     * @param _vestingPeriods The new vesting period list
     */
    function initialize(
        address _owner,
        address _lockToken,
        uint256[] memory _categoryIds,
        uint256[] memory _vestingPeriods
    ) external initializer {
        require(_owner != address(0), "LOCKON Vesting: owner is the zero address");
        require(_lockToken != address(0), "LOCKON Vesting: lockToken is the zero address");
        require(
            _categoryIds.length == _vestingPeriods.length,
            "LOCKON Vesting: categoryIds and vestingPeriods length mismatch"
        );

        // Initialize Ownable lib and set the owner
        __UUPSUpgradeable_init();
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __Pausable_init();
        lockToken = ILockToken(_lockToken);

        // Set vesting categories
        for (uint256 i = 0; i < _categoryIds.length;) {
            require(_vestingPeriods[i] > 0, "LOCKON Vesting: Vesting period must be greater than 0");
            vestingCategories[_categoryIds[i]] = _vestingPeriods[i];

            unchecked {
                ++i;
            }
        }
    }

    /* ============ View Functions ============ */

    /**
     * @dev This view function returns the latest end timestamp among all vesting periods
     *
     * @param user Address of the user initiates the vesting
     * @param categoryId A category id associated with the vesting schedule
     * @return latestEndTime The latest end timestamp (0 if no vesting periods exist)
     */
    function getVestingEndTime(address user, uint256 categoryId) external view returns (uint256) {
        VestingWallet[] storage wallets = userVestingWallets[user][categoryId];
        uint256 vestingPeriod = vestingCategories[categoryId];
        uint256 latestEndTime = 0;

        for (uint256 i = 0; i < wallets.length;) {
            uint256 endTime = wallets[i].startTime + vestingPeriod;
            if (endTime > latestEndTime) {
                latestEndTime = endTime;
            }
            unchecked {
                ++i;
            }
        }

        return latestEndTime;
    }

    /**
     * @dev Calculates the claimable and locked amounts of LOCK tokens across all vesting periods
     *
     * @param user Address of the user initiates the vesting
     * @param categoryId A category id associated with the vesting schedule
     * @return claimableAmount The total amount of tokens that can be claimed now
     * @return lockedAmount The total amount of tokens held in the contract for this user (including both claimable and unvested amounts)
     */
    function getVestingStatus(address user, uint256 categoryId) external view returns (uint256 claimableAmount, uint256 lockedAmount) {
        VestingWallet[] storage wallets = userVestingWallets[user][categoryId];
        uint256 vestingPeriod = vestingCategories[categoryId];

        for (uint256 i = 0; i < wallets.length;) {
            VestingWallet storage wallet = wallets[i];
            uint256 claimable = _claimable(wallet, vestingPeriod);
            claimableAmount += wallet.carriedOverClaimableAmount + claimable - wallet.claimedAmount;
            lockedAmount += wallet.carriedOverClaimableAmount + wallet.vestingAmount - wallet.claimedAmount;
            unchecked {
                ++i;
            }
        }

        return (claimableAmount, lockedAmount);
    }

    /**
     * @dev Returns the number of available vesting slots for a user-category pair
     * Matured periods are considered available
     *
     * @param user Address of the user
     * @param categoryId A category id associated with the vesting schedule
     * @return Number of available slots (0 to MAX_PARALLEL_VESTING)
     */
    function getAvailableSlots(address user, uint256 categoryId) external view returns (uint256) {
        VestingWallet[] storage wallets = userVestingWallets[user][categoryId];
        uint256 vestingPeriod = vestingCategories[categoryId];

        uint256 maturedCount = 0;
        for (uint256 i = 0; i < wallets.length;) {
            if (block.timestamp >= wallets[i].startTime + vestingPeriod) {
                unchecked {
                    ++maturedCount;
                }
            }
            unchecked {
                ++i;
            }
        }
        uint256 activeSlots = wallets.length - maturedCount;
        if (activeSlots >= MAX_PARALLEL_VESTING) {
            return 0;
        }
        return MAX_PARALLEL_VESTING - activeSlots;
    }

    /**
     * @dev Returns information about the oldest active (non-matured) vesting period
     *
     * @param user Address of the user
     * @param categoryId A category id associated with the vesting schedule
     * @return vestingAmount Remaining vesting amount (excluding claimable amount)
     * @return endTime End time of the oldest active vesting period
     */
    function getOldestActiveVestingInfo(address user, uint256 categoryId) external view returns (uint256 vestingAmount, uint256 endTime) {
        VestingWallet[] storage wallets = userVestingWallets[user][categoryId];
        uint256 vestingPeriod = vestingCategories[categoryId];
        (, uint256 oldestActiveIndex) = _findOldestPeriods(wallets, vestingPeriod);
        require(oldestActiveIndex != type(uint256).max, "LOCKON Vesting: No active vesting periods found");

        VestingWallet storage wallet = wallets[oldestActiveIndex];
        uint256 claimable = _claimable(wallet, vestingPeriod);
        vestingAmount = wallet.vestingAmount - claimable;
        endTime = wallet.startTime + vestingPeriod;
    }

    /* ============ Private Functions ============ */

    /**
     * @dev Calculates the claimable amount for a specific vesting period
     *
     * @param wallet Storage reference to the vesting wallet
     * @param vestingPeriod The vesting period for the category
     * @return The claimable amount for the specified vesting period
     */
    function _claimable(VestingWallet storage wallet, uint256 vestingPeriod) private view returns (uint256) {
        if (vestingPeriod != 0) {
            uint256 timeDiff = block.timestamp - wallet.startTime;
            uint256 claimableAmount = (wallet.vestingAmount * timeDiff) / vestingPeriod;
            if (claimableAmount < wallet.vestingAmount) {
                return claimableAmount;
            }
        }

        return wallet.vestingAmount;
    }

    /**
     * @dev Finds both the oldest matured period and oldest active (non-matured) period in one pass
     *
     * @param wallets Storage reference to the vesting wallets array
     * @param vestingPeriod The vesting period for the category
     * @return oldestMaturedIndex Index of oldest matured period (type(uint256).max if none)
     * @return oldestActiveIndex Index of oldest active (non-matured) period (type(uint256).max if none)
     */
    function _findOldestPeriods(
        VestingWallet[] storage wallets,
        uint256 vestingPeriod
    ) internal view returns (uint256 oldestMaturedIndex, uint256 oldestActiveIndex) {
        require(wallets.length > 0, "LOCKON Vesting: No vesting periods found");

        oldestMaturedIndex = type(uint256).max;
        oldestActiveIndex = type(uint256).max;
        uint256 oldestMaturedTime = type(uint256).max;
        uint256 oldestActiveTime = type(uint256).max;

        for (uint256 i = 0; i < wallets.length;) {
            VestingWallet storage wallet = wallets[i];
            uint256 startTime = wallet.startTime;
            bool isMatured = block.timestamp >= startTime + vestingPeriod;
            if (isMatured) {
                if (startTime < oldestMaturedTime) {
                    oldestMaturedTime = startTime;
                    oldestMaturedIndex = i;
                }
            } else {
                if (startTime < oldestActiveTime) {
                    oldestActiveTime = startTime;
                    oldestActiveIndex = i;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Removes a vesting period from the array using swap-and-pop
     *
     * @param wallets Storage reference to the vesting wallets array
     * @param index Index of the vesting period to remove
     */
    function _removeVestingPeriod(VestingWallet[] storage wallets, uint256 index) internal {
        wallets[index] = wallets[wallets.length - 1];
        wallets.pop();
    }

    /* ============ External Functions ============ */

    /**
     * @notice "PRIVILEGED FUNCTION: Add a new token amount for vesting and start a new
     * vesting schedule in the LOCKON Vesting contract"
     *
     * @param user Address of the user applying the vesting
     * @param amount The amount of token deposited for vesting
     * @param categoryId A category id associated with the vesting schedule
     */
    function deposit(address user, uint256 amount, uint256 categoryId)
        external
        onlyDepositGrantedOrOwner
        whenNotPaused
        nonReentrant
    {
        require(amount != 0, "LOCKON Vesting: Vesting amount must be greater than 0");
        require(user != address(0), "LOCKON Vesting: Zero address not allowed");
        uint256 vestingPeriod = vestingCategories[categoryId];
        require(vestingPeriod != 0, "LOCKON Vesting: Category do not exist");
        require(
            !lockToken.isBlacklisted(user), "LOCKON Vesting: User has been banned from all activities in LOCKON Vesting"
        );

        VestingWallet[] storage wallets = userVestingWallets[user][categoryId];

        (uint256 oldestMaturedIndex, uint256 oldestActiveIndex) = wallets.length > 0
            ? _findOldestPeriods(wallets, vestingPeriod)
            : (type(uint256).max, type(uint256).max);

        // If matured slots exist, reuse the oldest matured slot
        if (oldestMaturedIndex != type(uint256).max) {
            VestingWallet storage maturedWallet = wallets[oldestMaturedIndex];
            uint256 claimable = _claimable(maturedWallet, vestingPeriod);
            uint256 accumulated = maturedWallet.carriedOverClaimableAmount + claimable - maturedWallet.claimedAmount;
            maturedWallet.vestingAmount = amount;
            maturedWallet.carriedOverClaimableAmount = accumulated;
            maturedWallet.claimedAmount = 0;
            maturedWallet.startTime = block.timestamp;
            lockToken.safeTransferFrom(msg.sender, address(this), amount);
            emit VestingDeposited(msg.sender, user, amount, maturedWallet.vestingAmount, maturedWallet.startTime, categoryId, DepositType.MaturedReuse);
            return;
        }

        // If available slots exist, create a new slot
        if (wallets.length < MAX_PARALLEL_VESTING) {
            VestingWallet memory newWallet = VestingWallet({
                vestingAmount: amount,
                carriedOverClaimableAmount: 0,
                claimedAmount: 0,
                startTime: block.timestamp
            });
            wallets.push(newWallet);
            lockToken.safeTransferFrom(msg.sender, address(this), amount);
            emit VestingDeposited(msg.sender, user, amount, newWallet.vestingAmount, newWallet.startTime, categoryId, DepositType.NewSlot);
            return;
        }

        // If all slots full and no matured slots, update the oldest active period
        VestingWallet storage oldestWallet = wallets[oldestActiveIndex];
        uint256 oldestClaimable = _claimable(oldestWallet, vestingPeriod);
        uint256 oldestAccumulated = oldestClaimable + oldestWallet.carriedOverClaimableAmount - oldestWallet.claimedAmount;
        uint256 remainingVesting = oldestWallet.vestingAmount - oldestClaimable;
        oldestWallet.vestingAmount = remainingVesting + amount;
        oldestWallet.carriedOverClaimableAmount = oldestAccumulated;
        oldestWallet.claimedAmount = 0;
        oldestWallet.startTime = block.timestamp;

        lockToken.safeTransferFrom(msg.sender, address(this), amount);
        emit VestingDeposited(msg.sender, user, amount, oldestWallet.vestingAmount, oldestWallet.startTime, categoryId, DepositType.ActiveOverwrite);
    }

    /**
     * Allows user to claim all vested tokens from all vesting periods
     *
     * @param categoryId A category id associated with the vesting schedule
     */
    function claim(uint256 categoryId) external nonReentrant whenNotPaused {
        require(
            !lockToken.isBlacklisted(msg.sender),
            "LOCKON Vesting: User has been banned from all activities in LOCKON Vesting"
        );

        VestingWallet[] storage wallets = userVestingWallets[msg.sender][categoryId];
        uint256 vestingPeriod = vestingCategories[categoryId];

        uint256 totalClaimable = 0;
        for (uint256 i = wallets.length; i > 0;) {
            unchecked {
                --i;
            }
            VestingWallet storage wallet = wallets[i];
            uint256 claimable = _claimable(wallet, vestingPeriod);
            totalClaimable += claimable + wallet.carriedOverClaimableAmount - wallet.claimedAmount;

            bool isMatured = block.timestamp >= wallet.startTime + vestingPeriod;
            if (isMatured) {
                _removeVestingPeriod(wallets, i);
            } else {
                wallet.claimedAmount = claimable;
                wallet.carriedOverClaimableAmount = 0;
            }
        }
        require(totalClaimable > 0, "LOCKON Vesting: User has nothing to claim");

        lockToken.safeTransfer(msg.sender, totalClaimable);
        emit VestingClaimed(msg.sender, categoryId, totalClaimable);
    }

    /* ============ PRIVILEGED OWNER / GOVERNANCE Functions ============ */
    /**
     * @dev Add address to list allowed deposit address
     * @param _permissionedAddress Address to allow deposit
     */
    function addAddressDepositPermission(address _permissionedAddress) external onlyOwner {
        require(_permissionedAddress != address(0), "LOCKON Vesting: Zero address not allowed");
        require(
            !isAllowedDeposit[_permissionedAddress],
            "LOCKON Vesting: List allowed deposit address already contains this address"
        );
        listAllowedDeposit.push(_permissionedAddress);
        allowedDepositOneBasedIndexes[_permissionedAddress] = listAllowedDeposit.length;
        isAllowedDeposit[_permissionedAddress] = true;
        emit DepositPermissionStatusUpdated(
            msg.sender, _permissionedAddress, isAllowedDeposit[_permissionedAddress], block.timestamp
        );
    }

    /**
     * @dev Remove address from list allowed deposit address
     * @param _permissionedAddress Address to remove deposit permission
     */
    function removeAddressDepositPermission(address _permissionedAddress) external onlyOwner {
        require(_permissionedAddress != address(0), "LOCKON Vesting: Zero address not allowed");
        require(
            isAllowedDeposit[_permissionedAddress],
            "LOCKON Vesting: List allowed deposit address does not contain this address"
        );
        uint256 len = listAllowedDeposit.length;
        uint256 index = allowedDepositOneBasedIndexes[_permissionedAddress];
        address lastValue = listAllowedDeposit[len - 1];
        listAllowedDeposit[index - 1] = lastValue;
        allowedDepositOneBasedIndexes[lastValue] = index;
        // delete the index
        delete allowedDepositOneBasedIndexes[_permissionedAddress];
        listAllowedDeposit.pop();
        isAllowedDeposit[_permissionedAddress] = false;
        emit DepositPermissionStatusUpdated(
            msg.sender, _permissionedAddress, isAllowedDeposit[_permissionedAddress], block.timestamp
        );
    }

    /**
     * @dev Get list allowed deposit address
     */
    function getListAllowedDeposit() external view returns (address[] memory) {
        return listAllowedDeposit;
    }

    /**
     * @dev Set the vesting category list with its schedule
     *
     * @param _vestingCategoryIds The new category id list
     * @param _vestingCategoryValues The new list value for each vesting category id
     */
    function setVestingCategories(uint256[] calldata _vestingCategoryIds, uint256[] calldata _vestingCategoryValues)
        external
        onlyOwner
    {
        uint256 listIdLen = _vestingCategoryIds.length;
        require(
            _vestingCategoryValues.length == listIdLen,
            "LOCKON Vesting: The list for category ID and category value must have equal length"
        );
        for (uint256 i; i < listIdLen;) {
            vestingCategories[_vestingCategoryIds[i]] = _vestingCategoryValues[i];
            unchecked {
                ++i;
            }
        }
    }

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
     * @dev Override function from UUPS contract for upgrade authorize
     * @param newImplementation  Address of the new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
