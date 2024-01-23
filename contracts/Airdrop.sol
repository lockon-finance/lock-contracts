//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/ILockonVesting.sol";

/**
 * @title Airdrop contract
 * @author LOCKON
 * @dev Allows users to distribute LOCK Token for airdrop and claim rewards
 *
 */
contract Airdrop is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ Constants ============== */
    // Represents the category AIRDROP in the LOCKON vesting
    uint256 public constant AIRDROP_VESTING_CATEGORY_ID = 2;

    /* ============ State Variables ============ */
    // Address of LOCKON vesting contract
    address public lockonVesting;
    // Total airdrop amount of LOCK Tokens user can claim
    uint256 public totalPendingAirdropAmount;
    // Timestamp on which airdrop process start
    uint256 public startTimestamp;
    // Mapping of user address to amount of airdrop LOCK token reward
    mapping(address => uint256) public userPendingReward;
    // Mapping that keeps track of whether each address is allowed to receive to distribute to Airdrop contract
    mapping(address => bool) public isAllowedDistribute;
    // List address allowed to receive to distribute to Airdrop contract
    address[] public listAllowedDistribute;
    // Mapping that keeps track each user address index in the list allowed distribute address
    mapping(address => uint256) private allowedDistributeOneBasedIndexes;
    // Interface of the LOCK token contract
    IERC20 public lockToken;

    /* ============ Events ============ */

    /**
     * Emitted when an user distribute LOCK token as airdrop reward
     *
     * @param sender Address of the function executor
     * @param lockedAmount Amount of LOCK Tokens being locked
     * @param totalPendingAirdropAmount Total airdrop amount of LOCK Tokens user can claim
     */
    event AirdropRewardDistributed(address indexed sender, uint256 lockedAmount, uint256 totalPendingAirdropAmount);

    /**
     * @dev Emitted when an user claims their rewards
     *
     * @param sender Address of the function executor
     * @param userAmount The amount of LOCK token distributed to user for airdrop reward
     */
    event ClaimAirdropReward(address indexed sender, uint256 userAmount);

    /**
     * Emitted when the LOCKON Vesting address is updated
     *
     * @param lockonVesting New LOCKON Vesting address
     * @param timestamp Timestamp at which the address is updated
     */
    event LockonVestingUpdated(address lockonVesting, uint256 timestamp);

    /**
     * Emitted when the total airdrop amount is updated
     *
     * @param currentAirdropAmount New current total airdrop amount
     * @param timestamp Timestamp at which the amount is updated
     */
    event CurrentAirdropAmountUpdated(uint256 currentAirdropAmount, uint256 timestamp);

    /**
     * Emitted when the start timestamp is updated
     *
     * @param startTimestamp New start timestamp
     * @param timestamp Timestamp at which the airdrop start is updated
     */
    event StartTimestampUpdated(uint256 startTimestamp, uint256 timestamp);

    /**
     * Emitted when the admin allocates an amount of LOCK tokens to the contract
     *
     * @param owner Address of the owner to allocate LOCK tokens
     * @param amount Amount of LOCK tokens that are allocated
     */
    event LockTokenAllocated(address owner, uint256 amount);

    /**
     * Emitted when the admin withdraw an amount of LOCK tokens from the contract
     *
     * @param owner Address of the owner to withdraw LOCK tokens
     * @param amount Amount of LOCK tokens that are deallocated
     */
    event LockTokenDeallocated(address owner, uint256 amount);

    /**
     * Emitted when an address is added or removed from list allowed distribute address
     *
     * @param permissionedAddress address to be added or removed from list
     * @param distributePermission status for checking if address can distribute reward in Airdrop contract
     * @param timestamp Timestamp at which the address is added or removed
     */
    event DistributePermissionStatusUpdated(address permissionedAddress, bool distributePermission, uint256 timestamp);

    /**
     * @dev Modifier that only owner and address that allowed to distribute can call certain functions
     */
    modifier onlyDistributeGrantedOrOwner() {
        require(isAllowedDistribute[msg.sender] || msg.sender == owner(), "Airdrop: Forbidden");
        _;
    }

    /**
     * Initializes the Airdrop contract
     *
     * @param _owner Address of the owner of this contract
     * @param _lockonVesting Address of the LOCKON Vesting contract
     * @param _lockToken Address of the LOCK Token
     * @param _startTimestamp Timestamp on which airdrop process start
     */
    function initialize(address _owner, address _lockonVesting, address _lockToken, uint256 _startTimestamp)
        public
        initializer
    {
        // Initialize the contract and set the owner
        // This function should be called only once during deployment
        __Ownable_init_unchained(_owner);
        __UUPSUpgradeable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        lockonVesting = _lockonVesting;
        lockToken = IERC20(_lockToken);
        // Set staking start timestamp
        startTimestamp = _startTimestamp;
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    /* ============ External Functions ============ */

    /**
     * @dev Allow owner and address that allowed to update airdrop reward amount for list user address
     *
     * @param _listUserAddress List user address receive token airdrop
     * @param _amounts List airdrop amount value corresponding to each user
     */
    function distributeAirdropReward(address[] calldata _listUserAddress, uint256[] calldata _amounts)
        external
        whenNotPaused
        onlyDistributeGrantedOrOwner
    {
        uint256 listUserLen = _listUserAddress.length;
        require(
            _amounts.length == listUserLen, "Airdrop: The list for user address and amount value must have equal length"
        );
        uint256 totalAmount;
        for (uint256 i; i < listUserLen;) {
            require(
                _listUserAddress[i] != address(0) && _amounts[i] != 0,
                "Airdrop: Zero address or zero amount is not allowed"
            );
            userPendingReward[_listUserAddress[i]] += _amounts[i];
            totalAmount += _amounts[i];
            unchecked {
                i++;
            }
        }
        totalPendingAirdropAmount += totalAmount;
        emit AirdropRewardDistributed(msg.sender, listUserLen, totalPendingAirdropAmount);
    }

    /**
     * @dev Allows an user to claim their airdrop reward
     */
    function claimPendingReward() external whenNotPaused nonReentrant {
        require(block.timestamp >= startTimestamp, "Airdrop: Airdrop not start");
        uint256 userAmount = userPendingReward[msg.sender];
        require(userAmount != 0, "Airdrop: User does not have any airdrop reward to claim");
        userPendingReward[msg.sender] = 0;
        totalPendingAirdropAmount -= userAmount;
        // Approve the LOCKON vesting contract to spend the cumulative reward token
        lockToken.approve(lockonVesting, userAmount);
        ILockonVesting(lockonVesting).deposit(msg.sender, userAmount, AIRDROP_VESTING_CATEGORY_ID);
        emit ClaimAirdropReward(msg.sender, userAmount);
    }

    /* ============ PRIVILEGED OWNER / GOVERNANCE Functions ============ */
    /**
     * @dev Add address to list allowed distribute address
     * @param _permissionedAddress Address to be added to list
     */
    function addDistributePermission(address _permissionedAddress) external onlyOwner {
        require(_permissionedAddress != address(0), "Airdrop: Zero address not allowed");
        require(
            !isAllowedDistribute[_permissionedAddress],
            "Airdrop: List allowed distribute address already contains this address"
        );
        listAllowedDistribute.push(_permissionedAddress);
        allowedDistributeOneBasedIndexes[_permissionedAddress] = listAllowedDistribute.length;
        isAllowedDistribute[_permissionedAddress] = true;
        emit DistributePermissionStatusUpdated(
            _permissionedAddress, isAllowedDistribute[_permissionedAddress], block.timestamp
        );
    }

    /**
     * @dev Remove address from list allowed distribute address
     * @param _permissionedAddress Address to be removed from list
     */
    function removeDistributePermission(address _permissionedAddress) external onlyOwner {
        require(_permissionedAddress != address(0), "Airdrop: Zero address not allowed");
        require(
            isAllowedDistribute[_permissionedAddress],
            "Airdrop: List allowed distribute address does not contain this address"
        );
        uint256 len = listAllowedDistribute.length;
        uint256 index = allowedDistributeOneBasedIndexes[_permissionedAddress];
        address lastValue = listAllowedDistribute[len - 1];
        listAllowedDistribute[index - 1] = lastValue;
        allowedDistributeOneBasedIndexes[lastValue] = index;
        // delete the index
        delete allowedDistributeOneBasedIndexes[_permissionedAddress];
        listAllowedDistribute.pop();
        isAllowedDistribute[_permissionedAddress] = false;
        emit DistributePermissionStatusUpdated(
            _permissionedAddress, isAllowedDistribute[_permissionedAddress], block.timestamp
        );
    }

    /**
     * @dev Get list allowed distribute address
     */
    function getListAllowedDistribute() external view returns (address[] memory) {
        return listAllowedDistribute;
    }

    /**
     * @dev Allows the owner to add LOCK tokens to contract Airdrop
     *
     * @param _lockAmount The LOCK token amount to be added
     */
    function allocateLockToken(uint256 _lockAmount) external onlyOwner nonReentrant {
        lockToken.safeTransferFrom(msg.sender, address(this), _lockAmount);
        emit LockTokenAllocated(msg.sender, _lockAmount);
    }

    /**
     * @dev Allows the owner to withdraw LOCK tokens from contract Airdrop
     *
     * @param _lockAmount The LOCK token amount to be withdrawn
     */
    function deallocateLockToken(uint256 _lockAmount) external onlyOwner nonReentrant {
        lockToken.safeTransfer(msg.sender, _lockAmount);
        emit LockTokenDeallocated(msg.sender, _lockAmount);
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
        require(_lockonVesting != address(0), "Airdrop: Zero address not allowed");
        lockonVesting = _lockonVesting;
        emit LockonVestingUpdated(lockonVesting, block.timestamp);
    }

    /**
     * @dev Allows the owner to set the airdrop start timestamp
     *
     * @param _startTimestamp The new value for the start timestamp
     */
    function setStartTimestamp(uint256 _startTimestamp) external onlyOwner {
        startTimestamp = _startTimestamp;
        emit StartTimestampUpdated(startTimestamp, block.timestamp);
    }

    /**
     * @dev Override function from UUPS contract for upgrade authorize
     * @param newImplementation  Address of the new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
