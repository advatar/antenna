// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IHasher} from "../interfaces/IHasher.sol";

/// @notice Minimal incremental Merkle tree (depth 20) with pluggable hashing.
/// @dev This is a reference implementation intended for testnets and interop.
/// Production deployments should consider audited implementations and SNARK-friendly hashing.
abstract contract IncrementalMerkleTree {
    uint32 public constant TREE_DEPTH = 20;
    uint32 public constant MAX_LEAVES = uint32(1) << TREE_DEPTH;

    IHasher public immutable hasher;

    uint32 public nextIndex;
    bytes32[TREE_DEPTH] public zeros;
    bytes32[TREE_DEPTH] public filledSubtrees;

    bytes32 public root;

    // Root history for off-chain proof verification during brief reorgs / async syncing.
    mapping(bytes32 => bool) public isKnownRoot;

    event MerkleRootUpdated(bytes32 indexed newRoot, uint32 indexed nextIndex);

    constructor(IHasher _hasher, bytes32 zeroLeaf) {
        hasher = _hasher;

        zeros[0] = zeroLeaf;
        for (uint32 i = 1; i < TREE_DEPTH; i++) {
            zeros[i] = _hash(zeros[i - 1], zeros[i - 1]);
        }

        // Initialize filledSubtrees to zero values.
        for (uint32 i = 0; i < TREE_DEPTH; i++) {
            filledSubtrees[i] = zeros[i];
        }

        root = zeros[TREE_DEPTH - 1];
        isKnownRoot[root] = true;

        emit MerkleRootUpdated(root, nextIndex);
    }

    function _hash(bytes32 left, bytes32 right) internal view returns (bytes32) {
        // Note: hasher.hashLeftRight is pure, but called via external interface; this is fine for a reference contract.
        return hasher.hashLeftRight(left, right);
    }

    function _insert(bytes32 leaf) internal returns (uint32 index) {
        require(nextIndex < MAX_LEAVES, "Merkle tree full");

        uint32 currentIndex = nextIndex;
        nextIndex++;

        bytes32 currentLevelHash = leaf;

        for (uint32 level = 0; level < TREE_DEPTH; level++) {
            if (currentIndex % 2 == 0) {
                // Left node
                filledSubtrees[level] = currentLevelHash;
                currentLevelHash = _hash(currentLevelHash, zeros[level]);
            } else {
                // Right node
                currentLevelHash = _hash(filledSubtrees[level], currentLevelHash);
            }
            currentIndex /= 2;
        }

        root = currentLevelHash;
        isKnownRoot[root] = true;
        emit MerkleRootUpdated(root, nextIndex);

        return nextIndex - 1;
    }
}
