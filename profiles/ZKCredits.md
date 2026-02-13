
# ZK Usage Credits (RLN) Notes (Antenna profile)

This repo adopts the "ZK API usage credits" conceptual model for anonymous subagents:
- deposit once
- create many unlinkable requests
- prove membership + solvency in zero-knowledge
- RLN nullifiers prevent double-spends and allow slashing

Canonical reference:
- https://ethresear.ch/t/zk-api-usage-credits-llms-and-beyond/24104

## What this repo standardizes
- a wire shape for embedding a proof object: `antenna.zkcredits.v1`
- category manifest policy switches (`requiredProofs` includes `zkCredits`)
- attachment location: `event.auth.payload.zkCredits`

## What implementations must decide
- proving system: **Groth16 over BN254** (normative for MBP2P v0.1; other systems require a new profile/version)
- circuit and verification keys distribution
- whether verification is local, relay-assisted, or on-chain
- slashing mechanics and stake types (optional)


## Groth16 encoding (MBP2P v0.1)

The `antenna.zkcredits.v1` object uses a snarkjs-compatible Groth16 encoding:

- `proof.a`: `[a0,a1]`
- `proof.b`: `[[b00,b01],[b10,b11]]`
- `proof.c`: `[c0,c1]`
- `proof.inputs`: 5 public inputs in the required order:
  1. `merkleRoot`
  2. `nullifier`
  3. `signalHash`
  4. `ticketIndex`
  5. `cMax`

All are 256-bit field elements encoded as 0x-prefixed 64-hex strings in JSON.

On-chain verification uses `IZKCreditsVerifier.verifyProof(a,b,c,input)` where `input` is the same 5-element ordering.
