# Antenna ZK Usage Credits Contracts (Reference)

This folder provides **reference Solidity contracts** that support the MBP2P protocol’s
**RLN / ZK usage credits** profile.

These contracts are intentionally modular:
- the *membership tree* (identity commitments) is on-chain
- the *proof verifier* is an interface that is **Groth16/Bn254 (snarkjs) compatible** (other proof systems require an adapter contract)
- slashing is supported via a pluggable evidence verifier

> ⚠️ **Important:** The `KeccakHasher` in this reference implementation is **not SNARK-friendly**.
> Production deployments SHOULD use a SNARK-friendly hash (e.g., Poseidon) for Merkle trees and circuits.

## What’s included

- `src/MBZKCreditsEscrow.sol`
  - maintains an incremental Merkle tree of identity commitments (and optional deposit amount in the leaf)
  - emits roots for off-chain proof verification
  - optional nullifier registry (for global double-spend prevention when desired)
  - optional slashing hooks

- `src/VerifierRegistry.sol`
  - maps `verifierId` (bytes32) to verifier contract addresses

- `src/interfaces/IZKCreditsVerifier.sol`
  - **Groth16/Bn254** verifier interface for ZK spend proofs (snarkjs-style `Verifier.sol`)

- `src/interfaces/IDoubleSpendEvidenceVerifier.sol`
  - optional interface for verifying double-spend evidence and authorizing slashing

- `src/utils/IncrementalMerkleTree.sol`
  - minimal incremental Merkle tree (depth 20) with pluggable hashing

## Build / test

```bash
cd contracts
forge build
forge test -vv
```

## Interop notes

The off-chain MBP2P protocol embeds ZK usage credit proofs inside `antenna.zkcredits.v1` objects.
These contracts are designed to match that shape:

- Contract address is referenced as `eip155:<chainId>:<address>`
- `merkleRoot` is retrieved from `MBZKCreditsEscrow.root()`
- `verifierId` is a bytes32 identifier (recommended: `keccak256(utf8(verifierIdString))`)

See `spec/MBP2P-SPEC.md` and `profiles/ZKCredits.md` for full requirements.
