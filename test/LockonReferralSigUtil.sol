// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title LockonReferralSigUtil
 * @author LOCKON
 * @notice Claim signature for LOCK referral
 */
contract LockonReferralSigUtil {
    bytes32 internal immutable DOMAIN_SEPARATOR;

    constructor(bytes32 _DOMAIN_SEPARATOR) {
        DOMAIN_SEPARATOR = _DOMAIN_SEPARATOR;
    }

    /**
     * @dev Typehash for claim request
     */
    bytes32 public constant CLAIM_REQUEST_TYPEHASH = keccak256(
        "ClaimRequest(bytes32 requestId,address beneficiary,address tokenAddress,uint256 rewardAmount,bytes32 referralType)"
    );

    struct ClaimRequest {
        bytes32 requestId; // An ID for the reward claim request
        address beneficiary; // The address of the beneficiary of the reward claim request
        address tokenAddress; // The address of the token
        uint256 rewardAmount; // The amount of reward tokens to be claimed
        bytes32 referralType; // The referralType represents the referral type
    }

    /**
     * @dev computes the hash of a permit
     * @param _claimRequest Claim request data
     */
    function getStructHash(ClaimRequest memory _claimRequest) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                CLAIM_REQUEST_TYPEHASH,
                _claimRequest.requestId,
                _claimRequest.beneficiary,
                _claimRequest.tokenAddress,
                _claimRequest.rewardAmount,
                _claimRequest.referralType
            )
        );
    }

    /**
     * @dev computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
     * @param _claimRequest Claim request data
     */
    function getTypedDataHash(ClaimRequest memory _claimRequest) public view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, getStructHash(_claimRequest)));
    }
}
