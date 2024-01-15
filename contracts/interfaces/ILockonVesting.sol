// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ILockonVesting {
    function deposit(address user, uint256 amount, uint256 categoryId) external;
}
