// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ILockToken
 * @author LOCKON
 */
interface ILockToken is IERC20 {
    /**
     * Checks if an address is blacklisted
     * @param _userAddress The address to check for blacklist status
     * @return True if the address is blacklisted, false otherwise
     */
    function isBlacklisted(address _userAddress) external view returns (bool);
}
