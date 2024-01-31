//SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./interfaces/ILockonVesting.sol";

/**
 * @title MerkleAirdrop contract
 * @author LOCKON
 * @dev Allows users to distribute LOCK Token for airdrop and claim rewards
 */
contract MerkleAirdrop is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /* ============ Constants ============== */
    /**
     * @dev Represents the category AIRDROP in the LOCKON vesting
     */
    uint256 public constant AIRDROP_VESTING_CATEGORY_ID = 2;

    /* ============ State Variables ============ */
    /**
     * @dev The merkle root hashed from all user airdrop information
     */
    bytes32 public merkleRoot;
    /**
     * @dev Address of LOCKON vesting contract
     */
    address public lockonVesting;
    /**
     * @dev Timestamp on which airdrop process start
     */
    uint256 public startTimestamp;
    /**
     * @dev Mapping of user address to airdrop LOCK token reward amount
     */
    mapping(address => bool) public hasClaimed;
    /**
     * @dev Interface of the LOCK token contract
     */
    IERC20 public lockToken;
    /**
     * @dev Reserved storage space to allow for layout changes in the future.
     */
    uint256[50] private __gap;

    /* ============ Events ============ */
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
     * @param sender Address of the function executor
     * @param lockonVesting New LOCKON Vesting address
     * @param timestamp Timestamp at which the address is updated
     */
    event LockonVestingUpdated(address indexed sender, address lockonVesting, uint256 timestamp);

    /**
     * Emitted when the merkle root is updated
     *
     * @param sender Address of the function executor
     * @param merkleRoot New merkle root
     * @param timestamp Timestamp at which the hash is updated
     */
    event MerkleRootUpdated(address indexed sender, bytes32 merkleRoot, uint256 timestamp);

    /**
     * Emitted when the start timestamp is updated
     *
     * @param sender Address of the function executor
     * @param startTimestamp New start timestamp
     * @param timestamp Timestamp at which the airdrop start is updated
     */
    event StartTimestampUpdated(address indexed sender, uint256 startTimestamp, uint256 timestamp);

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
     * Initializes the Airdrop contract
     *
     * @param _owner Address of the owner of this contract
     * @param _lockonVesting Address of the LOCKON Vesting contract
     * @param _lockToken Address of the LOCK Token
     * @param _merkleRoot The merkle root hashed from all user airdrop information
     * @param _startTimestamp Timestamp on which airdrop process start
     */
    function initialize(
        address _owner,
        address _lockonVesting,
        address _lockToken,
        bytes32 _merkleRoot,
        uint256 _startTimestamp
    ) external initializer {
        // Initialize the contract and set the owner
        // This function should be called only once during deployment
        __Ownable_init_unchained(_owner);
        __UUPSUpgradeable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        lockonVesting = _lockonVesting;
        lockToken = IERC20(_lockToken);
        merkleRoot = _merkleRoot;
        // Set staking start timestamp
        startTimestamp = _startTimestamp;
    }

    /* ============ External Functions ============ */

    /**
     * @dev Allows an user to claim their airdrop reward
     *
     * @param _amount The amount of LOCK tokens to claim
     * @param _merkleProof The merkle proofs user use to verify
     */
    function claimPendingReward(uint256 _amount, bytes32[] calldata _merkleProof) external whenNotPaused nonReentrant {
        require(block.timestamp >= startTimestamp, "Airdrop: Airdrop not start");
        require(!hasClaimed[msg.sender], "Airdrop: User has already claimed this reward");
        bytes32 node = keccak256(abi.encodePacked(msg.sender, _amount));
        require(MerkleProof.verifyCalldata(_merkleProof, merkleRoot, node), "Airdrop: Invalid proof");
        hasClaimed[msg.sender] = true;
        // Approve the LOCKON vesting contract to spend the cumulative reward token
        lockToken.approve(lockonVesting, _amount);
        ILockonVesting(lockonVesting).deposit(msg.sender, _amount, AIRDROP_VESTING_CATEGORY_ID);
        emit ClaimAirdropReward(msg.sender, _amount);
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
     * @dev Allows the owner to withdraw LOCK tokens from contract MerkleAirdrop
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
        emit LockonVestingUpdated(msg.sender, lockonVesting, block.timestamp);
    }

    /**
     * @dev Allows the owner to set the new merkle root for new airdrop
     *
     * @param _merkleRoot The new value for the merkle root
     */
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
        emit MerkleRootUpdated(msg.sender, merkleRoot, block.timestamp);
    }

    /**
     * @dev Allows the owner to set the airdrop start timestamp
     *
     * @param _startTimestamp The new value for the start timestamp
     */
    function setStartTimestamp(uint256 _startTimestamp) external onlyOwner {
        startTimestamp = _startTimestamp;
        emit StartTimestampUpdated(msg.sender, startTimestamp, block.timestamp);
    }

    /**
     * @dev Override function from UUPS contract for upgrade authorize
     * @param newImplementation  Address of the new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
