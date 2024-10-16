// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import {LockToken} from "../contracts/LockToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LockonVesting} from "../contracts/LockonVesting.sol";
import {Airdrop} from "../contracts/Airdrop.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20Token is ERC20 {
    address public constant ACCOUNT_ONE = address(1);
    address public constant ACCOUNT_TWO = address(2);
    uint256 public constant TEST_ACCOUNT_INITIAL_BALANCE = 1000 ether;

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        _mint(msg.sender, 1_000_000 ether);
        _mint(ACCOUNT_ONE, TEST_ACCOUNT_INITIAL_BALANCE);
        _mint(ACCOUNT_TWO, TEST_ACCOUNT_INITIAL_BALANCE);
    }
}
// create mock contracts

contract MockAirdrop is Airdrop {
    uint256 public counter;

    function setup() public {
        counter = 10;
    }
}

contract UpgradeProxyAirdropTest is Test {
    address tokenProxy;
    address vestingProxy;
    address airdropProxy;
    address merkleAirdropProxy;
    uint256 constant validatorPrivateKey = 123;
    address public constant OWNER = address(bytes20(bytes("OWNER")));
    address public constant ACCOUNT_ONE = address(1);
    address public validator = vm.addr(validatorPrivateKey);

    function setUp() public {
        vm.startPrank(OWNER);
        LockToken token = new LockToken();
        LockonVesting lockonVesting = new LockonVesting();
        Airdrop airdrop = new Airdrop();
        // return data in bytes for calling initialization on each contract
        bytes memory tokenData = abi.encodeCall(token.initialize, ("LockToken", "LOCK", OWNER, validator));

        uint256[] memory vestingCategoryIds = new uint256[](0);
        uint256[] memory vestingPeriods = new uint256[](0);
        bytes memory lockonVestingData = abi.encodeCall(lockonVesting.initialize, (ACCOUNT_ONE, address(token), vestingCategoryIds, vestingPeriods));
        tokenProxy = address(new ERC1967Proxy(address(token), tokenData));
        vm.stopPrank();
        // using account one for vesting contract
        vm.startPrank(ACCOUNT_ONE);
        vestingProxy = address(new ERC1967Proxy(address(lockonVesting), lockonVestingData));

        vm.stopPrank();
        vm.startPrank(OWNER);
        bytes memory airdropData =
            abi.encodeCall(airdrop.initialize, (OWNER, address(lockonVesting), address(token), 0));
        airdropProxy = address(new ERC1967Proxy(address(airdrop), airdropData));
        vm.stopPrank();
    }

    function test_upgrade_airdrop() public {
        vm.startPrank(OWNER);
        MockAirdrop mock = new MockAirdrop();
        bytes memory data = abi.encodeCall(mock.setup, ());
        UUPSUpgradeable(airdropProxy).upgradeToAndCall(address(mock), data);
        assertEq(MockAirdrop(payable(airdropProxy)).counter(), 10);
    }
}
