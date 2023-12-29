// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

interface ILockonVesting {
    function deposit(address user, uint256 amount, uint256 categoryId) external;
}
