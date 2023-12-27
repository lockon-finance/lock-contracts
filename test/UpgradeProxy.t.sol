// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {LockToken} from "../contracts/LockToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LockStaking} from "../contracts/LockStaking.sol";
import {LockonVesting} from "../contracts/LockonVesting.sol";
import {IndexStaking} from "../contracts/IndexStaking.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20Token is ERC20 {
    address public constant accountOne = address(1);
    address public constant accountTwo = address(2);
    uint256 public constant testAccountInitialBalance = 1000 ether;

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        _mint(msg.sender, 1_000_000 ether);
        _mint(accountOne, testAccountInitialBalance);
        _mint(accountTwo, testAccountInitialBalance);
    }
}
// create mock contracts

contract MockLockToken is LockToken {
    uint256 public counter;

    function setup() public {
        counter = 10;
    }
}

contract MockLockStaking is LockStaking {
    uint256 public counter;

    function setup() public {
        counter = 10;
    }
}

contract MockIndexStaking is IndexStaking {
    uint256 public counter;

    function setup() public {
        counter = 10;
    }
}

contract MockLockonVesting is LockonVesting {
    uint256 public counter;

    function setup() public {
        counter = 10;
    }
}

contract UpgradeProxyTest is Test {
    address tokenProxy;
    address lockStakingProxy;
    address vestingProxy;
    address indexStakingProxy;
    uint256 constant validatorPrivateKey = 123;
    address public constant owner = address(bytes20(bytes("owner")));
    address public constant accountOne = address(1);
    address public validator = vm.addr(validatorPrivateKey);
    uint256 public constant testAccountInitialLockBalance = 1000 ether;
    MockERC20Token lpiToken;
    MockERC20Token lbiToken;

    function setUp() public {
        vm.startPrank(owner);
        LockToken token = new LockToken();
        LockStaking lockStaking = new LockStaking();
        IndexStaking indexStaking = new IndexStaking();
        LockonVesting lockonVesting = new LockonVesting();
        lpiToken = new MockERC20Token("Lockon Passive Index", "LPI");
        lbiToken = new MockERC20Token("Lockon Balance Index", "LBI");
        // return data in bytes for calling initialization on each contract
        bytes memory tokenData = abi.encodeCall(token.initialize, ("LockToken", "LOCK", owner, validator));
        bytes memory lockStakingData = abi.encodeCall(
            lockStaking.initialize,
            (
                owner,
                address(lockonVesting),
                validator, // For testing, use validator as penalty fee receiver also
                address(token),
                0,
                100000 ether,
                3,
                1
            )
        );
        bytes memory lockonVestingData = abi.encodeCall(lockonVesting.initialize, (accountOne, address(token)));
        tokenProxy = address(new ERC1967Proxy(address(token), tokenData));
        lockStakingProxy = address(new ERC1967Proxy(address(lockStaking), lockStakingData));
        vm.stopPrank();
        // using account one for vesting contract
        vm.prank(accountOne);
        vestingProxy = address(new ERC1967Proxy(address(lockonVesting), lockonVestingData));
        // initiate pools and token for index staking contract
        IndexStaking.PoolInfo memory firstPoolInfo = IndexStaking.PoolInfo(IERC20(address(lpiToken)), 0, block.number);
        IndexStaking.PoolInfo memory secondPoolInfo = IndexStaking.PoolInfo(IERC20(address(lbiToken)), 0, block.number);
        lpiToken = new MockERC20Token("Lockon Passive Index", "LPI");
        lbiToken = new MockERC20Token("Lockon Balance Index", "LBI");
        IndexStaking.PoolInfo[] memory poolInfos = new IndexStaking.PoolInfo[](2);
        poolInfos[0] = firstPoolInfo;
        poolInfos[1] = secondPoolInfo;
        bytes memory indexStakingData = abi.encodeCall(
            indexStaking.initialize,
            (owner, validator, address(lockonVesting), address(token), 100000 ether, "INDEX_STAKING", "1", poolInfos)
        );
        vm.prank(owner);
        indexStakingProxy = address(new ERC1967Proxy(address(indexStaking), indexStakingData));
    }

    function test_upgrade_lock_token() public {
        vm.startPrank(owner);
        MockLockToken mock = new MockLockToken();
        bytes memory data = abi.encodeCall(mock.setup, ());
        UUPSUpgradeable(tokenProxy).upgradeToAndCall(address(mock), data);
        assertEq(MockLockToken(tokenProxy).counter(), 10);
    }

    function test_upgrade_lock_staking() public {
        vm.startPrank(owner);
        MockLockStaking mock = new MockLockStaking();
        bytes memory data = abi.encodeCall(mock.setup, ());
        UUPSUpgradeable(lockStakingProxy).upgradeToAndCall(address(mock), data);
        assertEq(MockLockStaking(payable(lockStakingProxy)).counter(), 10);
    }

    function test_upgrade_index_staking() public {
        vm.startPrank(owner);
        MockIndexStaking mock = new MockIndexStaking();
        bytes memory data = abi.encodeCall(mock.setup, ());
        UUPSUpgradeable(indexStakingProxy).upgradeToAndCall(address(mock), data);
        assertEq(MockIndexStaking(payable(indexStakingProxy)).counter(), 10);
    }

    function test_upgrade_lockon_vesting() public {
        vm.startPrank(accountOne);
        MockLockonVesting mock = new MockLockonVesting();
        bytes memory data = abi.encodeCall(mock.setup, ());
        UUPSUpgradeable(vestingProxy).upgradeToAndCall(address(mock), data);
        assertEq(MockLockonVesting(payable(vestingProxy)).counter(), 10);
    }
}
