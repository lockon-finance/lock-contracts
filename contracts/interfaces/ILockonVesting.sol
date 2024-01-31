// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title LockonVesting interface
 * @author LOCKON
 */
interface ILockonVesting {
    /**
     * Add a new token amount for vesting and start a new
     * vesting schedule in the LOCKON Vesting contract
     * @param user Address of the user applying the vesting
     * @param amount The amount of token deposited for vesting
     * @param categoryId A category id associated with the vesting schedule
     */
    function deposit(address user, uint256 amount, uint256 categoryId) external;
}
