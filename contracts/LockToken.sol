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
    uint256 public constant MAX_SUPPLY = 10_000_000_000;
    uint256 public constant BASE_DENOMINATOR = 10_000;

    function initialize(
        string memory name,
        string memory symbol,
        address ownerAddress,
        address operatorAddress
    ) public initializer {
        __ERC20_init_unchained(name, symbol);
        uint256 amountMintToOwner = (MAX_SUPPLY * 6000) / BASE_DENOMINATOR; // 60%
        uint256 amountMintToOperator = (MAX_SUPPLY * 4000) / BASE_DENOMINATOR; // 40%
        _mint(ownerAddress, amountMintToOwner * (10 ** uint256(decimals())));
        _mint(
            operatorAddress,
            amountMintToOperator * (10 ** uint256(decimals()))
        );
    }
}
