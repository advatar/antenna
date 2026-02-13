// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Simple verifier registry: verifierId (bytes32) -> verifier contract address.
/// @dev verifierId SHOULD be `keccak256(utf8(verifierIdString))` to map from off-chain strings.
contract VerifierRegistry {
    address public owner;
    mapping(bytes32 => address) public verifiers;

    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event VerifierSet(bytes32 indexed verifierId, address indexed verifier);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address _owner) {
        owner = _owner;
        emit OwnerChanged(address(0), _owner);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero owner");
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    function setVerifier(bytes32 verifierId, address verifier) external onlyOwner {
        verifiers[verifierId] = verifier;
        emit VerifierSet(verifierId, verifier);
    }
}
