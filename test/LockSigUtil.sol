// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

contract LockSigUtils {
    bytes32 internal DOMAIN_SEPARATOR;

    function test() public {}

    constructor(bytes32 _DOMAIN_SEPARATOR) {
        DOMAIN_SEPARATOR = _DOMAIN_SEPARATOR;
    }

    bytes32 public constant CLAIM_REQUEST_TYPEHASH =
        keccak256("ClaimRequest(string requestId,address beneficiary,uint256 rewardAmount)");

    struct ClaimRequest {
        string requestId; // An ID for the reward claim request
        address beneficiary; // The address of the beneficiary of the reward claim request
        uint256 rewardAmount; // The amount of reward tokens to be claimed
    }

    // computes the hash of a permit
    function getStructHash(ClaimRequest memory _claimRequest) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                CLAIM_REQUEST_TYPEHASH,
                keccak256(bytes(_claimRequest.requestId)),
                _claimRequest.beneficiary,
                _claimRequest.rewardAmount
            )
        );
    }

    // computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
    function getTypedDataHash(ClaimRequest memory _claimRequest) public view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, getStructHash(_claimRequest)));
    }
}
