//SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.21;
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title LockToken
 * @author Lockon protocol
 *
 * Standard ERC20 Token contract with total supply is fixed at 100oku with upgradeable ability
 */
contract LockToken is Initializable, ERC20Upgradeable {
    /* ============ Constants ============== */

    // Maximum supply of Lock Token
    uint256 public constant MAX_SUPPLY = 10_000_000_000;
    // Represents the scaling factor used in calculations
    uint256 public constant BASE_DENOMINATOR = 10_000;

    /**
     * Initializes the Lock Token contract and mints tokens to owner and operator.
     *
     * @param name            The name of the ERC20 token
     * @param symbol          The symbol of the ERC20 token
     * @param ownerAddress    Address of the owner of this contract
     * @param operatorAddress Address of the operator
     */
    function initialize(
        string memory name,
        string memory symbol,
        address ownerAddress,
        address operatorAddress
    ) public initializer {
        // Initialize the ERC20 token with the provided name and symbol
        __ERC20_init_unchained(name, symbol);
        // Calculate the amount of tokens to mint to the owner (60% of MAX_SUPPLY)
        uint256 amountMintToOwner = (MAX_SUPPLY * 6000) / BASE_DENOMINATOR;
        // Calculate the amount of tokens to mint to the operator (40% of MAX_SUPPLY)
        uint256 amountMintToOperator = (MAX_SUPPLY * 4000) / BASE_DENOMINATOR;

        // Mint tokens to the owner and operator according to the calculated amounts
        _mint(ownerAddress, amountMintToOwner * (10 ** uint256(decimals())));
        _mint(
            operatorAddress,
            amountMintToOperator * (10 ** uint256(decimals()))
        );
    }
}
