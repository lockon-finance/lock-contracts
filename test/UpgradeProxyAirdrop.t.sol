// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {LockToken} from "../contracts/LockToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LockonVesting} from "../contracts/LockonVesting.sol";
import {Airdrop} from "../contracts/Airdrop.sol";
import {MerkleAirdrop} from "../contracts/MerkleAirdrop.sol";
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

contract MockAirdrop is Airdrop {
    uint256 public counter;

    function setup() public {
        counter = 10;
    }
}

contract MockMerkleAirdrop is MerkleAirdrop {
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
    address public constant owner = address(bytes20(bytes("owner")));
    address public constant accountOne = address(1);
    address public validator = vm.addr(validatorPrivateKey);
    uint256 public constant testAccountInitialLockBalance = 1000 ether;

    function setUp() public {
        vm.startPrank(owner);
        LockToken token = new LockToken();
        LockonVesting lockonVesting = new LockonVesting();
        Airdrop airdrop = new Airdrop();
        MerkleAirdrop merkleAirdrop = new MerkleAirdrop();
        // return data in bytes for calling initialization on each contract
        bytes memory tokenData = abi.encodeCall(token.initialize, ("LockToken", "LOCK", owner, validator));

        bytes memory lockonVestingData = abi.encodeCall(lockonVesting.initialize, (accountOne, address(token)));
        tokenProxy = address(new ERC1967Proxy(address(token), tokenData));
        vm.stopPrank();
        // using account one for vesting contract
        vm.startPrank(accountOne);
        vestingProxy = address(new ERC1967Proxy(address(lockonVesting), lockonVestingData));

        vm.stopPrank();
        vm.startPrank(owner);
        bytes memory airdropData =
            abi.encodeCall(airdrop.initialize, (owner, address(lockonVesting), address(token), 0));
        airdropProxy = address(new ERC1967Proxy(address(airdrop), airdropData));
        bytes memory merkleAirdropData = abi.encodeCall(
            merkleAirdrop.initialize,
            (
                owner,
                address(lockonVesting),
                address(token),
                0x94d7b8d37a07dc816d7d72922a0eb0d8d38caf144cc3e37c176cfbdb15aeb34a,
                100000
            )
        );
        merkleAirdropProxy = address(new ERC1967Proxy(address(merkleAirdrop), merkleAirdropData));
        vm.stopPrank();
    }

    function test_upgrade_airdrop() public {
        vm.startPrank(owner);
        MockAirdrop mock = new MockAirdrop();
        bytes memory data = abi.encodeCall(mock.setup, ());
        UUPSUpgradeable(airdropProxy).upgradeToAndCall(address(mock), data);
        assertEq(MockAirdrop(payable(airdropProxy)).counter(), 10);
    }

    function test_upgrade_merkle_airdrop() public {
        vm.startPrank(owner);
        MockMerkleAirdrop mock = new MockMerkleAirdrop();
        bytes memory data = abi.encodeCall(mock.setup, ());
        UUPSUpgradeable(merkleAirdropProxy).upgradeToAndCall(address(mock), data);
        assertEq(MockMerkleAirdrop(payable(merkleAirdropProxy)).counter(), 10);
    }
}
