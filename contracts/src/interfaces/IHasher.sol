// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Hash interface for Merkle tree hashing.
/// @dev Production systems SHOULD use a SNARK-friendly hash (e.g., Poseidon).
interface IHasher {
    function hashLeftRight(bytes32 left, bytes32 right) external pure returns (bytes32);
}
