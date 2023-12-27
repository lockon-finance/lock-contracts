//SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ILockonVesting.sol";

/**
 * @title Lockon Vesting contract
 * @author LOCKON protocol
 * @dev An ownable contract that can receive ERC20 LOCK tokens, and release these assets to the specified
 * wallet address, also referred to as "beneficiary", according to a vesting schedule.
 *
 * Any assets transferred to this contract will follow the vesting schedule as if they were locked from
 * the beginning. Consequently, if the vesting has already started, any amount of tokens sent to this
 * contract will (at least partly) be immediately releasable.
 *
 * NOTE:  Since the contract is {Ownable}, only wallet address that has ownership can create new vesting
 * schedule for new wallet (ownership can be transferred)
 *
 */

// TODO: Update all functions in contract vesting following GMX
contract LockonVesting is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    /* ============ Vesting Struct ============ */

    struct VestingWallet {
        address vestingAddress; // The address of the vesting wallet
        uint256 vestedAmount; // The total amount of tokens granted for vesting
        uint256 releasedAmount; // The amount of tokens already released from vesting
        uint256 vestingStartTime; // The starting time of the vesting period
        ILockonVesting.VestingTag vestingTag; // A custom tag associated with the vesting
    }

    /* ============ State Variables ============ */
    // Vesting duration
    uint256 public vestingDuration;
    // Address of the Lock Staking contract
    address public lockStakingContract;
    // Address of the Index Staking contract
    address public indexStakingContract;
    uint256 private _currentVestingId;
    // Mapping of vesting ID to VestingWallet struct, which stores information about vesting schedules
    mapping(uint256 => VestingWallet) public vestingWallet;
    // Mapping of vesting wallet address to a list of vesting IDs that have been allocated to it
    mapping(address => uint256[]) private userVestingIds;
    // Interface of the Lock token contract
    IERC20 public lockToken;

    /* ============ Events ============ */

    /**
     * Emitted when a new vesting wallet is added
     *
     * @param sender Address of the function executor
     * @param vestingAddress Address of the newly added vesting wallet
     * @param amount Total granted amount for vesting
     * @param vestingStartTime Starting time of the new vesting
     * @param vestingId Identifier for the vesting wallet
     * @param vestingTag A custom tag associated with the vesting
     */
    event VestingWalletAdded(
        address indexed sender,
        address vestingAddress,
        uint256 amount,
        uint256 vestingStartTime,
        uint256 vestingId,
        ILockonVesting.VestingTag vestingTag
    );

    /**
     * Emitted when a user claims vested tokens
     *
     * @param sender Address of the function executor
     * @param vestingIds List of the vesting wallet identifiers
     * @param releasedAmount Amount of tokens released to the user
     */
    event UserClaimedVesting(address indexed sender, uint256[] vestingIds, uint256 releasedAmount);

    /**
     * @dev Modifier that allows only the associated staking contracts to call certain functions along with owner
     */
    modifier onlyStakingContractOrOwner() {
        require(
            msg.sender == lockStakingContract || msg.sender == indexStakingContract || msg.sender == owner(),
            "Lockon Vesting: Forbidden"
        );
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
        vestingDuration = 300 days;
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    /* ============ View Functions ============ */

    /**
     * @dev Return all vesting ID that has been allocation to a specific address that is still in vesting
     */
    function getActiveVestingIdsForAddress(address _vestingAddress)
        public
        view
        returns (uint256[] memory, ILockonVesting.VestingTag[] memory)
    {
        uint256[] memory vestingIds = userVestingIds[_vestingAddress];
        uint256 len = vestingIds.length;
        ILockonVesting.VestingTag[] memory vestingTags = new ILockonVesting.VestingTag[](len);

        for (uint256 i; i < len;) {
            vestingTags[i] = vestingWallet[vestingIds[i]].vestingTag;

            unchecked {
                i++;
            }
        }

        return (vestingIds, vestingTags);
    }

    /**
     * @dev This view function returns a specific timestamp at which vesting process end.
     */
    function getVestingEndTime(uint256 _vestingId) public view returns (uint256) {
        require(_vestingId <= _currentVestingId, "Lockon Vesting: Invalid vesting id");
        return vestingWallet[_vestingId].vestingStartTime + vestingDuration;
    }

    /**
     * @dev Calculates the amount of lock tokens that can be released, based on the elapsed time and its historical
     * allocation.
     *
     * @param _vestingId ID of the vesting
     * @return The amount of tokens that can be released
     */
    function releasable(uint256 _vestingId) public view returns (uint256) {
        VestingWallet memory vestingInfo = vestingWallet[_vestingId];
        uint256 currentTime = block.timestamp;
        if (currentTime <= vestingInfo.vestingStartTime) {
            return 0;
        } else if (currentTime > getVestingEndTime(_vestingId)) {
            return vestingInfo.vestedAmount - vestingInfo.releasedAmount;
        } else {
            return ((vestingInfo.vestedAmount * (currentTime - vestingInfo.vestingStartTime)) / vestingDuration)
                - (vestingInfo.releasedAmount);
        }
    }

    /**
     * @dev Calculates the amount of lock tokens that can be released for multiple vesting ids
     *
     * @param _vestingIds IDs of the vesting
     */
    function releasables(uint256[] calldata _vestingIds) public view returns (uint256 totalReleasable) {
        uint256 len = _vestingIds.length;
        for (uint256 i; i < len;) {
            totalReleasable += releasable(_vestingIds[i]);

            unchecked {
                i++;
            }
        }
    }

    /* ============ External Functions ============ */

    /**
     * @notice PRIVILEGED OWNER FUNCTION: Add a new vesting wallet to the Lockon Vesting contract
     *
     * @param _vestingAddress Address of the vesting wallet to add
     * @param _amount Total vested amount
     * @param _vestingTag Description about the vesting
     */
    function addVestingWallet(address _vestingAddress, uint256 _amount, ILockonVesting.VestingTag _vestingTag)
        external
        onlyStakingContractOrOwner
    {
        require(_amount > 0, "Lockon Vesting: Vesting amount must be greater than 0");
        require(_vestingAddress != address(0), "Lockon Vesting: Zero address not allowed");

        // Increase vesting id
        _currentVestingId++;
        uint256 newVestingId = _currentVestingId;
        // Create a new VestingWallet struct to store the wallet's information
        vestingWallet[newVestingId] = VestingWallet(_vestingAddress, _amount, 0, block.timestamp, _vestingTag);
        // Update the list of vesting IDs for the vesting wallet's address
        userVestingIds[_vestingAddress].push(newVestingId);
        // Transfer the vested tokens from the owner to this contract
        lockToken.safeTransferFrom(msg.sender, address(this), _amount);

        emit VestingWalletAdded(msg.sender, _vestingAddress, _amount, block.timestamp, newVestingId, _vestingTag);
    }

    /**
     * Allows a user to claim vested tokens from a specific vesting wallet
     *
     * @param _vestingIds Ids of the vesting wallet from which tokens are to be claimed
     */
    function userClaimVesting(uint256[] calldata _vestingIds) external {
        // Keep track of the total claim amount of tokens
        uint256 totalClaim;
        uint256 length = _vestingIds.length;
        uint256 curVestingId = _currentVestingId;
        for (uint256 i; i < length;) {
            uint256 vestingId = _vestingIds[i];
            // Retrieve vesting information for the specified vesting wallet
            require(vestingId <= curVestingId, "Lockon Vesting: Invalid vesting id");
            // Check the amount of tokens that can be claimed
            uint256 _releasable = releasable(vestingId);
            if (_releasable > 0) {
                VestingWallet storage vestingInfo = vestingWallet[vestingId];
                require(msg.sender == vestingInfo.vestingAddress, "Lockon Vesting: Unauthorized to claim");
                // Update the released amount in the vesting information
                vestingInfo.releasedAmount += _releasable;
                totalClaim += _releasable;
            }
            unchecked {
                i++;
            }
        }
        // Transfer the claimed tokens to the vesting wallet
        lockToken.safeTransfer(msg.sender, totalClaim);

        emit UserClaimedVesting(msg.sender, _vestingIds, totalClaim);
    }

    /* ============ PRIVILEGED OWNER / GOVERNANCE Functions ============ */

    /**
     * @dev Set the address of the Lock Staking contract
     * @param _lockStakingContract  Address of the Lock Staking contract
     */
    function setLockStakingContract(address _lockStakingContract) external onlyOwner {
        require(_lockStakingContract != address(0), "Lockon Vesting: Zero address not allowed");
        lockStakingContract = _lockStakingContract;
    }

    /**
     * @dev Set the address of the Index Staking contract
     * @param _indexStakingContract  Address of the Index Staking contract
     */
    function setIndexStakingContract(address _indexStakingContract) external onlyOwner {
        require(_indexStakingContract != address(0), "Lockon Vesting: Zero address not allowed");
        indexStakingContract = _indexStakingContract;
    }

    /**
     * @dev Set the vesting duration
     *
     * @param _vestingDuration The new value for the vesting duration
     */
    function setVestingDuration(uint256 _vestingDuration) external onlyOwner {
        vestingDuration = _vestingDuration;
    }

    /**
     * @dev Override function from UUPS contract for upgrade authorize
     * @param newImplementation  Address of the new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
