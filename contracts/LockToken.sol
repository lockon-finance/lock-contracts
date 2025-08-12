//SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title LockToken
 * @author LOCKON
 *
 * Standard ERC20 Token contract with total supply is fixed at 100oku with upgradeable ability
 */
contract LockToken is Initializable, OwnableUpgradeable, ERC20Upgradeable, UUPSUpgradeable {
    /* ============ Constants ============== */

    /**
     * @dev Maximum supply of Lock Token
     */
    uint256 private constant MAX_SUPPLY = 10_000_000_000;
    /**
     * @dev Represents the scaling factor used in calculations
     */
    uint256 private constant BASE_DENOMINATOR = 10_000;
    /**
     * @dev LOCK token allocation percentage to the owner
     */
    uint256 private constant OWNER_ALLOCATION_PERCENTAGE = 4000;
    /**
     * @dev LOCK token allocation percentage to the management
     */
    uint256 private constant MANAGEMENT_ALLOCATION_PERCENTAGE = 6000;

    /* ============ State Variables ============ */

    /**
     * @dev Mapping that keeps track of whether each address is blocked
     */
    mapping(address => bool) private _isBlacklisted;

    /**
     * @dev Reserved storage space to allow for layout changes in the future.
     */
    uint256[49] private __gap;

    /* ============ Events ============ */

    /**
     * Emitted when an address is banned from activities
     *
     * @param sender Address of the function executor
     * @param userAddress address to be added to blacklist
     * @param timestamp Timestamp at which the address is banned
     */
    event UserBlacklistAdded(address indexed sender, address indexed userAddress, uint256 timestamp);

    /**
     * Emitted when an address is unbanned from activities
     *
     * @param sender Address of the function executor
     * @param userAddress address to be removed from blacklist
     * @param timestamp Timestamp at which the address is unbanned
     */
    event UserBlacklistRemoved(address indexed sender, address indexed userAddress, uint256 timestamp);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * Initializes the Lock Token contract and mints tokens to owner and management.
     *
     * @param name            The name of the ERC20 token
     * @param symbol          The symbol of the ERC20 token
     * @param ownerAddress    Address of the owner of this contract
     * @param managementAddress Address of the management
     */
    function initialize(string memory name, string memory symbol, address ownerAddress, address managementAddress)
        external
        initializer
    {
        require(ownerAddress != address(0), "LockToken: ownerAddress is the zero address");
        require(managementAddress != address(0), "LockToken: managementAddress is the zero address");
        __UUPSUpgradeable_init();
        // Initialize the contract's owner
        __Ownable_init(ownerAddress);
        // Initialize the ERC20 token with the provided name and symbol
        __ERC20_init(name, symbol);
        // Calculate the amount of tokens to mint to the owner (40% of MAX_SUPPLY)
        uint256 amountMintToOwner = (MAX_SUPPLY * OWNER_ALLOCATION_PERCENTAGE) / BASE_DENOMINATOR;
        // Calculate the amount of tokens to mint to the management (60% of MAX_SUPPLY)
        uint256 amountMintToManagement = (MAX_SUPPLY * MANAGEMENT_ALLOCATION_PERCENTAGE) / BASE_DENOMINATOR;
        // Mint tokens to the owner and management according to the calculated amounts
        _mint(ownerAddress, amountMintToOwner * (10 ** uint256(decimals())));
        _mint(managementAddress, amountMintToManagement * (10 ** uint256(decimals())));
    }

    /**
     * @dev Adds an address to the blacklist, preventing it from transferring or approving tokens
     * @param _userAddress Address to be added to the blacklist
     */
    function addBlacklistUser(address _userAddress) external onlyOwner {
        require(_userAddress != address(0), "LOCK Token: Zero address not allowed");
        require(!_isBlacklisted[_userAddress], "LOCK Token: Blacklist already contains this address");

        _isBlacklisted[_userAddress] = true;
        emit UserBlacklistAdded(msg.sender, _userAddress, block.timestamp);
    }

    /**
     * @dev Removes an address from the blacklist, allowing it to transfer and approve tokens again
     * @param _userAddress Address to be removed from the blacklist
     */
    function removeBlacklistUser(address _userAddress) external onlyOwner {
        require(_userAddress != address(0), "LOCK Token: Zero address not allowed");
        require(_isBlacklisted[_userAddress], "LOCK Token: Blacklist does not contain this address");

        _isBlacklisted[_userAddress] = false;
        emit UserBlacklistRemoved(msg.sender, _userAddress, block.timestamp);
    }

    /**
     * @dev Returns whether an address is blacklisted
     * @param _userAddress Address to check blacklist status
     * @return bool True if the address is blacklisted, false otherwise
     */
    function isBlacklisted(address _userAddress) public view returns (bool) {
        return _isBlacklisted[_userAddress];
    }

    /**
     * @dev Override function from UUPS contract for upgrade authorize
     * @param newImplementation  Address of the new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Override of ERC20 _update function to check blacklist status before token transfers
     * @param from Address sending the tokens
     * @param to Address receiving the tokens
     * @param value Amount of tokens to transfer
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        require(!isBlacklisted(msg.sender), "LOCK Token: sender is blocked");
        require(!isBlacklisted(from), "LOCK Token: transfer from is blocked");
        require(!isBlacklisted(to), "LOCK Token: transfer to is blocked");

        super._update(from, to, value);
    }

    /**
     * @dev Override of ERC20 _approve function to check blacklist status before approval
     * @param owner Address that owns the tokens
     * @param spender Address that will be allowed to spend the tokens
     * @param value Amount of tokens to approve
     * @param emitEvent Whether to emit the Approval event
     */
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual override {
        require(!isBlacklisted(owner), "LOCK Token: owner is blocked");
        require(!isBlacklisted(spender), "LOCK Token: spender is blocked");

        super._approve(owner, spender, value, emitEvent);
    }
}
