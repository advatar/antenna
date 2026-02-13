// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Groth16 verifier interface for MBP2P ZK usage-credits spend proofs.
/// @dev This intentionally matches the function name and ABI used by **snarkjs**-generated Solidity verifiers:
///      `verifyProof(uint256[2], uint256[2][2], uint256[2], uint256[]/uint256[N]) -> bool`.
///
/// MBP2P v0.1 fixes the public input arity to 5 and orders them as:
///   input[0] = uint256(merkleRoot)
///   input[1] = uint256(nullifier)
///   input[2] = uint256(signalHash)
///   input[3] = ticketIndex
///   input[4] = cMax
interface IZKCreditsVerifier {
    function verifyProof(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[5] calldata input
    ) external view returns (bool);
}
