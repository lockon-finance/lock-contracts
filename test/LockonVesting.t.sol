// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {LockToken} from "../contracts/LockToken.sol";
import {LockonVesting} from "../contracts/LockonVesting.sol";

contract LockonVestingTest is Test {
    LockonVesting public lockonVesting;
    LockToken public lockToken;
    address public owner = address(bytes20(bytes("owner")));
    address public accountOne = address(1);
    address public accountTwo = address(2);

    error OwnableUnauthorizedAccount(address account);
    error ERC20InsufficientAllowance(
        address spender,
        uint256 allowance,
        uint256 needed
    );

    function setUp() public {
        vm.startPrank(owner);
        lockToken = new LockToken();
        lockToken.initialize("LockToken", "LOCK", owner, accountOne);
        lockonVesting = new LockonVesting();
        deal(owner, 100 ether);
    }

    function initilizeVestingContract() public {
        lockonVesting.initialize(owner, address(lockToken));
    }

    function addVestingWallet(
        address _vestedAddress,
        uint256 _vestingAmount,
        uint64 _vestingDuration,
        string memory _vestingTag
    ) public {
        lockToken.approve(address(lockonVesting), _vestingAmount);
        lockonVesting.addVestingWallet(
            _vestedAddress,
            _vestingAmount,
            _vestingDuration,
            _vestingTag
        );
    }

    function test__owner_set_lockToken() public {
        initilizeVestingContract();
        lockonVesting.setLockTokenAddress(accountOne);
        address newLockToken = address(lockonVesting.lockToken());
        assertEq(accountOne, newLockToken);
    }

    function test__set_lockToken_fail() public {
        initilizeVestingContract();
        address oldLockToken = address(lockonVesting.lockToken());
        // Only owner check
        vm.stopPrank();
        vm.prank(accountOne);
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUnauthorizedAccount.selector,
                accountOne
            )
        );
        lockonVesting.setLockTokenAddress(accountOne);
        address newLockToken = address(lockonVesting.lockToken());
        assertEq(oldLockToken, newLockToken);
        // Rules violation
        vm.expectRevert("Lockon Vesting: Zero address not allowed");
        vm.prank(owner);
        lockonVesting.setLockTokenAddress(address(0));
    }

    function test__owner_add_vesting_wallet() public {
        initilizeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        lockToken.approve(address(lockonVesting), vestingAmount);
        vm.recordLogs();
        lockonVesting.addVestingWallet(accountOne, vestingAmount, 60, "tag"); // Vesting for 60 seconds
        Vm.Log[] memory entries = vm.getRecordedLogs();
        /**
         * Make sure that event add is emitted
         *
         * @dev Get the entries at index 1 since on add vesting function call,
         * event transfer from also get emitted at index 0
         */
        assertEq(
            entries[1].topics[0],
            keccak256(
                "VestingWalletAdded(address,address,uint256,uint256,uint256,uint256,string)"
            )
        );
    }

    function test__add_vesting_wallet_fail() public {
        initilizeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        // Only owner check
        vm.stopPrank();
        vm.prank(accountOne);
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUnauthorizedAccount.selector,
                accountOne
            )
        );
        lockonVesting.addVestingWallet(accountOne, vestingAmount, 60, "tag");
        // Not enough allowance check
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20InsufficientAllowance.selector,
                address(lockonVesting),
                lockToken.allowance(owner, address(lockonVesting)),
                vestingAmount
            )
        );
        vm.startPrank(owner);
        lockonVesting.addVestingWallet(accountTwo, vestingAmount, 60, "tag");
        // Not enough balance check
        vm.expectRevert("Lockon Vesting: Sender balance is not enough!");
        lockonVesting.addVestingWallet(
            accountTwo,
            vestingAmount * 10_000_000_000,
            60,
            "tag"
        );
        // Add vesting for zero address
        vm.expectRevert("Lockon Vesting: Zero address not allowed");
        lockonVesting.addVestingWallet(address(0), vestingAmount, 60, "tag");
        // Add vesting with amount equal to zero
        vm.expectRevert(
            "Lockon Vesting: Vesting amount must be greater than 0"
        );
        lockonVesting.addVestingWallet(accountTwo, 0, 60, "tag");
    }

    function test__vesting_view_function() public {
        initilizeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        addVestingWallet(accountOne, vestingAmount, 60, "tag");
        // Releaseable = 0 at the time start vesting
        assertEq(lockonVesting.releasable(1), 0);
        skip(100); // Skip 100s
        addVestingWallet(accountOne, vestingAmount, 60, "tag");
        uint256[] memory accountOneVestingIds = lockonVesting.getVestingIds(
            accountOne
        );
        assertEq(accountOneVestingIds.length, 2);
        assertEq(accountOneVestingIds[0], 1);
        assertEq(accountOneVestingIds[1], 2);

        (, , , uint256 vestingID1StartTime, , ) = lockonVesting.vestingWallet(
            1
        );
        assertEq(lockonVesting.getVestingEndTime(1), vestingID1StartTime + 60);

        assertEq(lockonVesting.releasable(1), vestingAmount); // 100s has passed, the first vesting has been fully unlocked
    }

    function test__vesting_view_function_fail() public {
        initilizeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        addVestingWallet(accountOne, vestingAmount, 60, "tag");
        vm.expectRevert("Lockon Vesting: Invalid vesting id");
        lockonVesting.getVestingEndTime(2);
        vm.expectRevert("Lockon Vesting: Invalid vesting id");
        lockonVesting.releasable(2);
    }

    function test__vesting_claim_vesting() public {
        initilizeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        uint64 vestingDuration = 60;
        /**
         * First vesting, claim partial amount of token since it's not fully unlocked
         *
         */
        uint256 firstVestingStartTimestamp = block.timestamp;
        addVestingWallet(accountOne, vestingAmount, vestingDuration, "tag");
        skip(40); // Skip 40s
        // Re-caculate claimable amount to assure the logic implement in the SC is correct
        uint256 claimableAmount = (vestingAmount *
            (block.timestamp - firstVestingStartTimestamp)) / vestingDuration;
        uint256 accountOneBalanceBefore = lockToken.balanceOf(accountOne);
        assertEq(claimableAmount, lockonVesting.releasable(1));
        vm.recordLogs();
        vm.stopPrank();
        vm.prank(accountOne);
        lockonVesting.userClaimVesting(1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        /**
         * Make sure that event claim is emitted
         *
         * @dev Get the entries at index 1 since on claim vesting function call,
         * event transfer also get emitted at index 0
         */
        assertEq(
            entries[1].topics[0],
            keccak256("UserClaimedVesting(address,uint256,uint256)")
        );
        (, uint256 eventRealeasedAmount) = abi.decode(
            entries[1].data,
            (uint256, uint256)
        );
        uint256 accountOneBalanceAfter = lockToken.balanceOf(accountOne);
        assertEq(
            eventRealeasedAmount,
            accountOneBalanceAfter - accountOneBalanceBefore
        );

        /**
         * Second vesting, claim fully amount of token since it's passed end time
         *
         */
        vm.startPrank(owner);
        addVestingWallet(accountOne, vestingAmount, vestingDuration, "tag");
        vm.stopPrank();
        skip(60); // Skip 60s
        // Claimable amount should be equal to vesting amount
        assertEq(vestingAmount, lockonVesting.releasable(2));
        accountOneBalanceBefore = lockToken.balanceOf(accountOne);
        vm.prank(accountOne);
        lockonVesting.userClaimVesting(2);
        accountOneBalanceAfter = lockToken.balanceOf(accountOne);
        assertEq(
            vestingAmount,
            accountOneBalanceAfter - accountOneBalanceBefore
        );
    }

    function test__vesting_claim_vesting_fail() public {
        initilizeVestingContract();
        uint256 vestingAmount = 100 * 1e18;
        uint64 vestingDuration = 60;
        // Trying to claim when not unlocked
        addVestingWallet(accountOne, vestingAmount, vestingDuration, "tag");
        vm.expectRevert("Lockon Vesting: Nothing to claim");
        vm.stopPrank();
        vm.prank(accountOne);
        lockonVesting.userClaimVesting(1);
        // Trying to claim invalid vesting id
        vm.expectRevert("Lockon Vesting: Invalid vesting id");
        lockonVesting.userClaimVesting(2);
        // Trying to claim other person vesting
        vm.expectRevert("Lockon Vesting: Unauthorized to claim");
        vm.prank(accountTwo);
        lockonVesting.userClaimVesting(1);
    }

    function test___receiver_func() public {
        initilizeVestingContract();
        (bool sent, ) = address(lockonVesting).call{value: 1 ether}("");
        require(sent, "Failed to send Ether");
        payable(address(lockonVesting)).transfer(1 ether);
    }
}
