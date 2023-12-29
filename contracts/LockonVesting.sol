//SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

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
    using SafeERC20 for IERC20;
    /* ============ Vesting Struct ============ */

    struct VestingWallet {
        address userAddress; // The address of the user initiates the vesting
        uint256 vestingAmount; // The total amount of tokens granted for vesting
        uint256 claimableAmount; // The total amount of tokens user can claim
        uint256 claimedAmount; // The amount of tokens already released from vesting based on current schedule
        uint256 startTime; // The starting time of the vesting period
        uint256 categoryId; // A category id associated with the vesting
    }

    /* ============ State Variables ============ */
    /**
     * Mapping of vesting category id to its vesting schedule
     *
     * Ex: category id 0 represents category LOCK STAKING, has a vesting schedule of 100 days
     * => categoryId[0] = 100 days;
     */
    mapping(uint256 => uint256) public vestingCategories;
    // Mapping of user address to VestingWallet struct based on vesting category id, which stores vesting information
    mapping(address => mapping(uint256 => VestingWallet)) public userVestingWallet;
    // Mapping that keeps track of whether each address is allowed to receive to deposit to LOCKON Vesting contract
    mapping(address => bool) public isAllowedDeposit;
    // Mapping that keeps track of whether each address is banned from all activities in LOCKON Vesting
    mapping(address => bool) public isBlacklistUser;
    // List address allowed to receive to deposit to LOCKON Vesting contract
    address[] public listAllowedDeposit;
    // Mapping that keeps track each user address index in the list allowed deposit address
    mapping(address => uint256) private allowedDepositOneBasedIndexes;
    // List address banned from any activities in LOCKON Vesting, only owner can see this
    address[] private blacklist;
    // Mapping that keeps track each user address index in the blacklist
    mapping(address => uint256) private blacklistOneBasedIndexes;
    // Interface of the LOCK token contract
    IERC20 public lockToken;

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
     */
    event VestingDeposited(
        address indexed sender,
        address user,
        uint256 depositAmount,
        uint256 vestingAmount,
        uint256 startTime,
        uint256 categoryId
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
     * @param addr address
     * @param depositPermission status for checking if address can deposit to LOCKON Vesting
     * @param timestamp Timestamp at which the address is added or removed
     */
    event DepositPermissionStatusUpdated(address addr, bool depositPermission, uint256 timestamp);

    /**
     * Emitted when an address is banned from activities
     *
     * @param addr address
     * @param isBanned status for checking if address is banned
     * @param timestamp Timestamp at which the address is banned
     */
    event UserBlacklistUserAdded(address addr, bool isBanned, uint256 timestamp);

    /**
     * Emitted when an address is unbanned from activities
     *
     * @param addr address
     * @param isBanned status for checking if address is banned
     * @param timestamp Timestamp at which the address is unbanned
     */
    event UserBlacklistUserRemoved(address addr, bool isBanned, uint256 timestamp);

    /**
     * @dev Modifier that only owner and address that allowed to deposit can call certain functions
     */
    modifier onlyDepositGrantedOrOwner() {
        require(isAllowedDeposit[msg.sender] || msg.sender == owner(), "LOCKON Vesting: Forbidden");
        _;
    }

    /**
     * Initializes the vesting contract
     *
     * @param _owner      Address of the owner of this contract
     * @param _lockToken  Address of the ERC20 LOCK Token
     */
    function initialize(address _owner, address _lockToken) public initializer {
        // Initialize Ownable lib and set the owner
        __Ownable_init_unchained(_owner);

        lockToken = IERC20(_lockToken);
        vestingCategories[0] = 300 days; // index 0 represents category LOCK STAKING
        vestingCategories[1] = 300 days; // index 1 represents category INDEX STAKING
        vestingCategories[2] = 300 days; // index 2 represents category AIRDROP
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    /**
     * @dev This view function returns a specific timestamp at which vesting process end.
     *
     * @param user Address of the user initiates the vesting
     * @param categoryId A category id associated with the vesting schedule
     */
    function getVestingEndTime(address user, uint256 categoryId) public view returns (uint256) {
        return userVestingWallet[user][categoryId].startTime + vestingCategories[categoryId];
    }

    /**
     * @dev Calculates the total claimable amount of LOCK tokens, based on the elapsed time
     *
     * @param user Address of the user initiates the vesting
     * @param categoryId A category id associated with the vesting schedule
     * @return The amount of tokens that can be claimed
     */
    function currentTotalClaimable(address user, uint256 categoryId) external view returns (uint256) {
        VestingWallet storage vestingInfo = userVestingWallet[user][categoryId];
        if (vestingInfo.vestingAmount == 0) {
            return 0;
        }

        uint256 timeDiff = block.timestamp - vestingInfo.startTime;
        uint256 claimableAmount = (vestingInfo.vestingAmount * timeDiff / vestingCategories[categoryId]);

        if (claimableAmount < vestingInfo.vestingAmount) {
            return vestingInfo.claimableAmount + claimableAmount - vestingInfo.claimedAmount;
        }

        return vestingInfo.claimableAmount + vestingInfo.vestingAmount - vestingInfo.claimedAmount;
    }

    /**
     * @dev Calculates the cumulative amount of LOCK tokens vested in the current vesting schedule
     *
     * @param user Address of the user initiates the vesting
     * @param categoryId A category id associated with the vesting schedule
     * @return The cumulative amount of LOCK tokens vested in the current schedule
     */
    function _claimable(address user, uint256 categoryId) internal view returns (uint256) {
        VestingWallet storage vestingInfo = userVestingWallet[user][categoryId];
        if (vestingInfo.vestingAmount == 0) {
            return 0;
        }

        uint256 timeDiff = block.timestamp - vestingInfo.startTime;
        uint256 claimableAmount = (vestingInfo.vestingAmount * timeDiff / vestingCategories[categoryId]);

        if (claimableAmount < vestingInfo.vestingAmount) {
            return claimableAmount;
        }

        return vestingInfo.vestingAmount;
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
    {
        require(!isBlacklistUser[user], "LOCKON Vesting: User has been banned from all activities in LOCKON Vesting");
        require(amount != 0, "LOCKON Vesting: Vesting amount must be greater than 0");
        require(user != address(0), "LOCKON Vesting: Zero address not allowed");

        VestingWallet storage vestingInfo = userVestingWallet[user][categoryId];
        uint256 claimableAmount = _claimable(user, categoryId);
        // Calculate based on the cumulative claimable vested amount of the current vesting and the previous
        // vesting schedules and deduct the vested amount user had claimed in the current vesting
        vestingInfo.claimableAmount = claimableAmount + vestingInfo.claimableAmount - vestingInfo.claimedAmount;
        // Calculate vesting amount based on new amount and the remaining
        vestingInfo.vestingAmount = vestingInfo.vestingAmount + amount - claimableAmount;
        // Start a new vesting schedule
        vestingInfo.startTime = block.timestamp;
        vestingInfo.claimedAmount = 0;

        lockToken.safeTransferFrom(msg.sender, address(this), amount);

        emit VestingDeposited(msg.sender, user, amount, vestingInfo.vestingAmount, vestingInfo.startTime, categoryId);
    }

    /**
     * Allows user to claim all vested tokens
     *
     * @param categoryId A category id associated with the vesting schedule
     */
    function claim(uint256 categoryId) external nonReentrant whenNotPaused {
        require(
            !isBlacklistUser[msg.sender], "LOCKON Vesting: User has been banned from all activities in LOCKON Vesting"
        );
        uint256 claimableAmount = _claimable(msg.sender, categoryId);
        VestingWallet storage vestingInfo = userVestingWallet[msg.sender][categoryId];
        require(
            claimableAmount != 0 || (vestingInfo.claimableAmount - vestingInfo.claimedAmount != 0),
            "LOCKON Vesting: User has nothing to claim"
        );

        // Calculate based on the cumulative claimable vested amount of the current vesting and the previous
        // vesting schedules and deduct the vested amount user had claimed in the current vesting
        uint256 totalTokenClaim = claimableAmount + vestingInfo.claimableAmount - vestingInfo.claimedAmount;
        vestingInfo.claimedAmount = claimableAmount;
        // Reset the cumulative claimable vested amount
        vestingInfo.claimableAmount = 0;

        lockToken.safeTransfer(msg.sender, totalTokenClaim);

        emit VestingClaimed(msg.sender, categoryId, totalTokenClaim);
    }

    /* ============ PRIVILEGED OWNER / GOVERNANCE Functions ============ */
    /**
     * @dev Add address to list allowed deposit address
     * @param _addr Address
     */
    function addAddressDepositPermission(address _addr) external onlyOwner {
        require(_addr != address(0), "LOCKON Vesting: Zero address not allowed");
        require(
            !isAllowedDeposit[_addr],
            "LOCKON Vesting: List allowed deposit address already contains this address"
        );
        listAllowedDeposit.push(_addr);
        allowedDepositOneBasedIndexes[_addr] = listAllowedDeposit.length;
        isAllowedDeposit[_addr] = true;
        emit DepositPermissionStatusUpdated(_addr, isAllowedDeposit[_addr], block.timestamp);
    }

    /**
     * @dev Remove address from list allowed deposit address
     * @param _addr Address
     */
    function removeAddressDepositPermission(address _addr) external onlyOwner {
        require(_addr != address(0), "LOCKON Vesting: Zero address not allowed");
        require(
            isAllowedDeposit[_addr],
            "LOCKON Vesting: List allowed deposit address does not contain this address"
        );
        uint256 len = listAllowedDeposit.length;
        uint256 index = allowedDepositOneBasedIndexes[_addr];
        address lastValue = listAllowedDeposit[len - 1];
        listAllowedDeposit[index - 1] = lastValue;
        allowedDepositOneBasedIndexes[lastValue] = index;
        // delete the index
        delete allowedDepositOneBasedIndexes[_addr];
        listAllowedDeposit.pop();
        isAllowedDeposit[_addr] = false;
        emit DepositPermissionStatusUpdated(_addr, isAllowedDeposit[_addr], block.timestamp);
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
            "The list for category ID and category value must have equal length"
        );
        for (uint256 i; i < listIdLen;) {
            vestingCategories[_vestingCategoryIds[i]] = _vestingCategoryValues[i];
            unchecked {
                i++;
            }
        }
    }

    /**
     * @dev Add address to list banned address
     * @param _addr Address
     */
    function addBlacklistUser(address _addr) external onlyOwner {
        require(_addr != address(0), "LOCKON Vesting: Zero address not allowed");
        require(!isBlacklistUser[_addr], "LOCKON Vesting: Blacklist already contains this address");
        blacklist.push(_addr);
        blacklistOneBasedIndexes[_addr] = blacklist.length;
        isBlacklistUser[_addr] = true;
        emit UserBlacklistUserAdded(_addr, isBlacklistUser[_addr], block.timestamp);
    }

    /**
     * @dev Remove address from list banned address
     * @param _addr Address
     */
    function removeBlacklistUser(address _addr) external onlyOwner {
        require(_addr != address(0), "LOCKON Vesting: Zero address not allowed");
        require(isBlacklistUser[_addr], "LOCKON Vesting: Blacklist does not contain this address");
        uint256 len = blacklist.length;
        uint256 index = blacklistOneBasedIndexes[_addr];
        address lastValue = blacklist[len - 1];
        blacklist[index - 1] = lastValue;
        blacklistOneBasedIndexes[lastValue] = index;
        // delete the index
        delete blacklistOneBasedIndexes[_addr];
        blacklist.pop();
        isBlacklistUser[_addr] = false;
        emit UserBlacklistUserRemoved(_addr, isBlacklistUser[_addr], block.timestamp);
    }

    /**
     * @dev Get list banned address
     */
    function getBlacklist() external view onlyOwner returns (address[] memory) {
        return blacklist;
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
