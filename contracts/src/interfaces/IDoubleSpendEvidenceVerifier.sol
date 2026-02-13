// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Optional interface for verifying evidence of RLN double-spending and authorizing slashing.
/// @dev In RLN-style systems, double-signing with the same nullifier can allow recovering a secret.
/// This interface allows plugging in a verifier (on-chain or off-chain assisted) that determines
/// whether a slash is valid.
///
/// A minimal production deployment MAY omit on-chain evidence verification and perform slashing
/// through governance or an operator-run process.
interface IDoubleSpendEvidenceVerifier {
    function verifyDoubleSpendEvidence(
        bytes calldata evidence,
        bytes32 nullifier
    ) external view returns (bool);
}
