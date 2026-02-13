# On-chain Contracts (Reference)

This repository includes reference Solidity contracts under `contracts/` to support the MBP2P **ZK usage credits** profile.

## Contracts

- `VerifierRegistry.sol`
  - maps `verifierId: bytes32` -> verifier contract address
  - intended to make verifier selection explicit and upgradeable without redeploying the escrow

- `MBZKCreditsEscrow.sol`
  - incremental Merkle tree for membership (identity commitments)
  - root publication for off-chain proof verification
  - optional on-chain nullifier registry (`enforceNullifiers`)
  - optional slashing via `IDoubleSpendEvidenceVerifier`

## Design notes

### Proof system

MBP2P v0.1 targets **Groth16 over BN254** for spend-proof verification. The escrow calls a verifier contract through `IZKCreditsVerifier`, which matches snarkjs-generated `Verifier.sol` signatures.


### Merkle leaf
The reference escrow uses:

`leaf = H(identityCommitment, depositWei)`

This allows a ZK circuit to bind solvency to the deposited amount using Merkle membership.

### Hash function
The reference `KeccakHasher` is suitable for testnets and non-ZK Merkle proofs, but is not SNARK-friendly.
Production deployments SHOULD use Poseidon (or another SNARK-friendly hash) and a circuit that matches.

### Nullifier enforcement
Most MBP2P deployments will prefer **off-chain** nullifier enforcement:
- relays keep a rolling window of seen nullifiers per category policy
- if a nullifier is reused, relays can drop the message and optionally initiate slashing

On-chain nullifier enforcement requires every usage ticket to be registered on-chain, which is typically too expensive.

## Deployment (Foundry)

```bash
cd contracts
forge build
forge script script/Deploy.s.sol --rpc-url <RPC> --broadcast --verify
```
