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
    uint256 public constant MAX_SUPPLY = 10_000_000_000;
    /**
     * @dev Represents the scaling factor used in calculations
     */
    uint256 public constant BASE_DENOMINATOR = 10_000;

    /* ============ State Variables ============ */

    /**
     * @dev Reserved storage space to allow for layout changes in the future.
     */
    uint256[50] private __gap;

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
        // Initialize the ERC20 token with the provided name and symbol
        __ERC20_init_unchained(name, symbol);
        // Initialize the contract's owner
        __Ownable_init_unchained(ownerAddress);
        __UUPSUpgradeable_init();
        // Calculate the amount of tokens to mint to the owner (40% of MAX_SUPPLY)
        uint256 amountMintToOwner = (MAX_SUPPLY * 4000) / BASE_DENOMINATOR;
        // Calculate the amount of tokens to mint to the management (60% of MAX_SUPPLY)
        uint256 amountMintToManagement = (MAX_SUPPLY * 6000) / BASE_DENOMINATOR;

        // Mint tokens to the owner and management according to the calculated amounts
        _mint(ownerAddress, amountMintToOwner * (10 ** uint256(decimals())));
        _mint(managementAddress, amountMintToManagement * (10 ** uint256(decimals())));
    }

    /**
     * @dev Override function from UUPS contract for upgrade authorize
     * @param newImplementation  Address of the new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
