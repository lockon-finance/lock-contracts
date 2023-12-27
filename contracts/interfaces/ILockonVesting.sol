// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

interface ILockonVesting {
    enum VestingTag {
        LOCK_STAKING_ADD,
        LOCK_STAKING_EXTEND,
        LOCK_STAKING_WITHDRAW,
        LOCK_STAKING_CLAIM,
        INDEX_STAKING_CLAIM
    }

    function addVestingWallet(address _vestingAddress, uint256 _amount, VestingTag _vestingTag) external;
}
