//SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.21;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Lockon Vesting contract
 * @author Lockon protocol
 * @dev Lockon vesting is an ownable contract that can receive ERC20 lock tokens, and release these
 * assets to the specified wallet address, also referred to as "beneficiary", according to a vesting schedule.
 *
 * Any assets transferred to this contract will follow the vesting schedule as if they were locked from the beginning.
 * Consequently, if the vesting has already started, any amount of tokens sent to this contract will (at least partly)
 * be immediately releasable.
 *
 * NOTE:  Since the contract is {Ownable}, only wallet address that has ownership can create new vesting schedule for new wallet (ownership can be transferred)
 *
 */
contract LockonVesting is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    /* ============ Vesting Struct ============ */
    struct VestingWallet {
        address vestingAddress; // The address of the vesting wallet
        uint256 vestedAmount; // The total amount of tokens granted for vesting
        uint256 releasedAmount; // The amount of tokens already released from vesting
        uint256 vestingStartTime; // The starting time of the vesting period
        uint256 vestingDuration; // The duration over which vesting occurs
        string vestingTag; // A custom tag associated with the vesting
    }

    /* ============ State Variables ============ */
    uint256 private _currentVestingId;
    // Mapping of vesting ID to VestingWallet struct, which stores information about vesting schedules
    mapping(uint256 => VestingWallet) public vestingWallet;
    // Mapping of wallet/contract address => array of vestingID
    mapping(address => uint256[]) private userVestingIds;
    // Interface of the Lock token contract
    IERC20 public lockToken;

    /* ============ Events ============ */
    // Emitted when a new vesting wallet is added
    event VestingWalletAdded(
        address indexed sender, // Address of function executor
        address vestingWallet, // Address of the newly added vesting wallet
        uint256 amount, // Total granted amount for vesting
        uint256 vestingStartTime, // The starting time of the new vesting
        uint256 vestingDuration, // Duration of the vesting period
        uint256 vestingId, // Id for the vesting wallet
        string vestingTag // A custom tag associated with the vesting
    );

    // Emitted when a user claims vested tokens
    event UserClaimedVesting(
        address indexed sender, // Address of function executor
        uint256 vestingId, // Id for the vesting wallet
        uint256 releasedAmount // Amount of tokens released to the user
    );

    /**
     * Initializes the vesting contract
     *
     * @param _owner      Address of the owner of this contract
     * @param _lockToken  Address of the ERC20 Lock Token
     */
    function initialize(address _owner, address _lockToken) public initializer {
        // Initialize Ownable lib and set the owner
        __Ownable_init_unchained(_owner);
        // Set the lockToken to the provided ERC20 Lock Token address
        lockToken = IERC20(_lockToken);
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    /* ============ View Functions ============ */

    /**
     * @dev Return all vesting ID that has been allocation to a specific address
     */
    function getVestingIds(
        address _vestingWallet
    ) public view returns (uint256[] memory) {
        return userVestingIds[_vestingWallet];
    }

    /**
     * @dev This view function returns a specific timestamp at which vesting process end.
     */
    function getVestingEndTime(
        uint256 _vestingId
    ) public view returns (uint256) {
        require(
            _vestingId <= _currentVestingId,
            "Lockon Vesting: Invalid vesting id"
        );
        return
            vestingWallet[_vestingId].vestingStartTime +
            vestingWallet[_vestingId].vestingDuration;
    }

    /**
     * @dev Calculates the amount of lock tokens that can be released, based on the elapsed time and its historical allocation.
     *
     * @param _vestingId ID of the vesting
     * @return The amount of tokens that can be released
     */
    function releasable(uint256 _vestingId) public view returns (uint256) {
        require(
            _vestingId <= _currentVestingId,
            "Lockon Vesting: Invalid vesting id"
        );
        VestingWallet memory vestingInfo = vestingWallet[_vestingId];
        uint64 currentTime = uint64(block.timestamp);
        if (currentTime <= vestingInfo.vestingStartTime) {
            return 0;
        } else if (currentTime > getVestingEndTime(_vestingId)) {
            return vestingInfo.vestedAmount - vestingInfo.releasedAmount;
        } else {
            return
                ((vestingInfo.vestedAmount *
                    (currentTime - vestingInfo.vestingStartTime)) /
                    vestingInfo.vestingDuration) - (vestingInfo.releasedAmount);
        }
    }

    /* ============ External Functions ============ */

    /**
     * @notice PRIVILEGED OWNER FUNCTION: Add a new vesting wallet to the Lockon Vesting contract
     *
     * @param _vestingAddress Address of the vesting wallet to add
     * @param _amount Total vested amount
     * @param _vestingDuration Duration of the vesting period
     */
    function addVestingWallet(
        address _vestingAddress,
        uint256 _amount,
        uint64 _vestingDuration,
        string memory _vestingTag
    ) external onlyOwner {
        require(
            _amount > 0,
            "Lockon Vesting: Vesting amount must be greater than 0"
        );
        require(
            _vestingAddress != address(0),
            "Lockon Vesting: Zero address not allowed"
        );

        // Increase vesting id
        _currentVestingId++;
        // Create a new VestingWallet struct to store the wallet's information
        vestingWallet[_currentVestingId] = VestingWallet(
            _vestingAddress,
            _amount,
            0,
            block.timestamp,
            _vestingDuration,
            _vestingTag
        );
        // Update the list of vesting IDs for the vesting wallet's address
        userVestingIds[_vestingAddress].push(_currentVestingId);
        require(
            _amount <= lockToken.balanceOf(msg.sender),
            "Lockon Vesting: Sender balance is not enough!"
        );
        // Transfer the vested tokens from the owner to this contract
        lockToken.safeTransferFrom(msg.sender, address(this), _amount);

        emit VestingWalletAdded(
            msg.sender,
            _vestingAddress,
            _amount,
            block.timestamp,
            _vestingDuration,
            _currentVestingId,
            _vestingTag
        );
    }

    /**
     * Allows a user to claim vested tokens from a specific vesting wallet
     *
     * @param _vestingId Id of the vesting wallet from which tokens are to be claimed
     */
    function userClaimVesting(uint256 _vestingId) external {
        // Retrieve vesting information for the specified vesting wallet
        VestingWallet storage vestingInfo = vestingWallet[_vestingId];
        require(
            _vestingId <= _currentVestingId,
            "Lockon Vesting: Invalid vesting id"
        );
        require(
            msg.sender == vestingInfo.vestingAddress,
            "Lockon Vesting: Unauthorized to claim"
        );
        // Check the amount of tokens that can be claimed
        uint256 _releasable = releasable(_vestingId);

        require(_releasable > 0, "Lockon Vesting: Nothing to claim");

        // Update the released amount in the vesting information
        vestingInfo.releasedAmount += _releasable;

        // Transfer the claimed tokens to the vesting wallet
        lockToken.safeTransfer(vestingInfo.vestingAddress, _releasable);

        emit UserClaimedVesting(msg.sender, _vestingId, _releasable);
    }

    /**
     * @notice PRIVILEGED OWNER FUNCTION: Update the address of the ERC20 Lock Token contract.
     *
     * @param _lockToken The new address of the ERC20 Lock Token contract to be used for vesting.
     * @dev This function allows the contract owner to change the Lock Token contract address if needed.
     */
    function setLockTokenAddress(address _lockToken) external onlyOwner {
        require(
            _lockToken != address(0),
            "Lockon Vesting: Zero address not allowed"
        );
        lockToken = IERC20(_lockToken);
    }
}
