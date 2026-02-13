// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IHasher} from "../interfaces/IHasher.sol";

/// @notice Reference hasher using keccak256(left || right).
/// @dev NOT SNARK-friendly. Use Poseidon (or similar) in production ZK circuits.
contract KeccakHasher is IHasher {
    function hashLeftRight(bytes32 left, bytes32 right) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(left, right));
    }
}
