// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IncrementalMerkleTree} from "./utils/IncrementalMerkleTree.sol";
import {IHasher} from "./interfaces/IHasher.sol";
import {IZKCreditsVerifier} from "./interfaces/IZKCreditsVerifier.sol";
import {IDoubleSpendEvidenceVerifier} from "./interfaces/IDoubleSpendEvidenceVerifier.sol";
import {VerifierRegistry} from "./VerifierRegistry.sol";

/// @title MBZKCreditsEscrow (Reference)
/// @notice Reference on-chain component for MBP2P's RLN/ZK usage credits profile.
///
/// This contract provides:
/// - identity commitment registration into an incremental Merkle tree
/// - root publication for off-chain proof verification
/// - optional on-chain nullifier registry (global double-spend prevention)
/// - optional slashing hook using a pluggable evidence verifier
///
/// ## Leaf format
/// In the ZK usage credits design, the prover needs to bind their solvency to a deposited stake.
/// A common approach is to include the stake amount (and optional other parameters) in the Merkle leaf.
///
/// This reference contract sets:
///   leaf = H(identityCommitment, depositWei)
///
/// where H is the configured `IHasher`.
///
/// ⚠️ For production ZK systems, use a SNARK-friendly H (Poseidon), and ensure your circuit uses the same H.
contract MBZKCreditsEscrow is IncrementalMerkleTree {
    struct IdentityInfo {
        // The "ID" in the usage-credits design: typically Hash(secret_k)
        bytes32 identityCommitment;
        uint256 depositWei;
        address depositor;
        bool slashed;
        uint32 leafIndex;
    }

    VerifierRegistry public immutable verifierRegistry;

    // identityCommitment -> info
    mapping(bytes32 => IdentityInfo) public identities;
    mapping(bytes32 => bool) public isIdentityRegistered;

    // Optional global nullifier registry. If enabled, `consume()` will mark nullifiers as used.
    bool public immutable enforceNullifiers;
    mapping(bytes32 => bool) public nullifierUsed;

    event IdentityDeposited(
        bytes32 indexed identityCommitment,
        uint256 depositWei,
        uint32 indexed leafIndex,
        bytes32 leaf,
        bytes32 merkleRoot,
        address indexed depositor
    );

    event NullifierConsumed(
        bytes32 indexed nullifier,
        bytes32 indexed signalHash,
        bytes32 indexed merkleRoot,
        bytes32 verifierId,
        uint256 ticketIndex,
        uint256 cMax,
        address relayer
    );

    event IdentitySlashed(
        bytes32 indexed identityCommitment,
        uint256 amountWei,
        address indexed recipient,
        bytes32 evidenceVerifierId
    );

    constructor(
        IHasher _hasher,
        bytes32 zeroLeaf,
        VerifierRegistry _verifierRegistry,
        bool _enforceNullifiers
    ) IncrementalMerkleTree(_hasher, zeroLeaf) {
        verifierRegistry = _verifierRegistry;
        enforceNullifiers = _enforceNullifiers;
    }

    /// @notice Register a new identity commitment by depositing stake.
    /// @dev This reference implementation requires a single fixed deposit at registration time.
    ///      Top-ups are not supported because the leaf format includes depositWei.
    function deposit(bytes32 identityCommitment) external payable returns (uint32 leafIndex, bytes32 leaf) {
        require(msg.value > 0, "deposit=0");
        require(!isIdentityRegistered[identityCommitment], "already registered");

        leaf = hasher.hashLeftRight(identityCommitment, bytes32(msg.value));
        leafIndex = _insert(leaf);

        IdentityInfo memory info = IdentityInfo({
            identityCommitment: identityCommitment,
            depositWei: msg.value,
            depositor: msg.sender,
            slashed: false,
            leafIndex: leafIndex
        });

        identities[identityCommitment] = info;
        isIdentityRegistered[identityCommitment] = true;

        emit IdentityDeposited(identityCommitment, msg.value, leafIndex, leaf, root, msg.sender);
        return (leafIndex, leaf);
    }

    /// @notice Verify and (optionally) consume a usage-credit ticket for a given message `signalHash`.
    ///
    /// @param merkleRoot Root used in the proof (MUST be a known root).
    /// @param nullifier RLN nullifier (uniqueness for a ticket index).
    /// @param signalHash Hash of the MBP2P message/event being authorized.
    /// @param verifierId Identifier for the verifier contract to use (bytes32).
    /// @param ticketIndex The ticket index `i` (public input to the circuit).
    /// @param cMax The maximum cost bound for this action (public input).
    function consume(
        bytes32 merkleRoot,
        bytes32 nullifier,
        bytes32 signalHash,
        bytes32 verifierId,
        uint256 ticketIndex,
        uint256 cMax,
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c
    ) external {
        require(isKnownRoot[merkleRoot], "unknown root");

        if (enforceNullifiers) {
            require(!nullifierUsed[nullifier], "nullifier used");
        }

        address verifier = verifierRegistry.verifiers(verifierId);
        require(verifier != address(0), "no verifier");

        uint256[5] memory input;
        input[0] = uint256(merkleRoot);
        input[1] = uint256(nullifier);
        input[2] = uint256(signalHash);
        input[3] = ticketIndex;
        input[4] = cMax;

        bool ok = IZKCreditsVerifier(verifier).verifyProof(a, b, c, input);
        require(ok, "invalid proof");

        if (enforceNullifiers) {
            nullifierUsed[nullifier] = true;
        }

        emit NullifierConsumed(nullifier, signalHash, merkleRoot, verifierId, ticketIndex, cMax, msg.sender);
    }

    /// @notice Slash a registered identity if valid double-spend evidence is provided.
    /// @dev This is OPTIONAL; many deployments will do evidence verification off-chain.
    ///
    /// The evidence format is verifier-specific and handled by an external verifier contract.
    ///
    /// @param identityCommitment The commitment to slash (must be registered).
    /// @param evidenceVerifierId Which evidence verifier to use (bytes32).
    /// @param evidence Opaque evidence bytes (e.g., two conflicting RLN signatures).
    /// @param nullifier The nullifier that was double-spent.
    /// @param recipient Where to send the slashed stake.
    function slash(
        bytes32 identityCommitment,
        bytes32 evidenceVerifierId,
        bytes calldata evidence,
        bytes32 nullifier,
        address payable recipient
    ) external {
        require(isIdentityRegistered[identityCommitment], "not registered");
        IdentityInfo storage info = identities[identityCommitment];
        require(!info.slashed, "already slashed");
        require(recipient != address(0), "zero recipient");

        address evidenceVerifier = verifierRegistry.verifiers(evidenceVerifierId);
        require(evidenceVerifier != address(0), "no evidence verifier");

        bool ok = IDoubleSpendEvidenceVerifier(evidenceVerifier).verifyDoubleSpendEvidence(evidence, nullifier);
        require(ok, "invalid evidence");

        info.slashed = true;

        uint256 amt = info.depositWei;
        info.depositWei = 0;

        (bool sent, ) = recipient.call{value: amt}("");
        require(sent, "transfer failed");

        emit IdentitySlashed(identityCommitment, amt, recipient, evidenceVerifierId);
    }
}
