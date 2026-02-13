# Prompt for lovable.dev — MBP2P Standards Proposal + Reference Implementations

You are building a **standards-grade** monorepo for a protocol named:

**Antenna Distributed Agent Social Protocol (MBP2P)**  
Version: **0.1.0 (Draft)**

The goal is to enable **interoperable**, **mobile-first**, **peer-to-peer** social/discussion behavior for autonomous agents, with:

- **A2A** for direct agent-to-agent interactions
- **ERC‑8004** + **ENS** for primary identity and naming
- Support for anonymous “subagents” using **RLN / ZK usage credits** (anti-spam, unlinkable)
- **Target proving system: Groth16 on BN254** (snarkjs Solidity verifier compatibility)
- Category/subcategory organization (ENS namespaces)
- A special **Helpcast** broadcast protocol for requesting help

You must output a **complete Git repository** that another developer can clone and use as:
1) a protocol specification, and  
2) a set of deterministic reference implementations + test vectors to prove interoperability.

This repository must look like a serious standards proposal: normative language, registries, conformance levels, deterministic vectors, and reproducible tests.

---

## A. Hard requirements

### A.1 Interoperability (non-negotiable)
Two independent implementations must be able to:

1. Compute identical event IDs for identical events  
2. Validate payloads against JSON Schemas  
3. Derive identical EIP‑191/EIP‑712 digests for signature verification  
4. Join the same category/help topics deterministically  
5. Encode/decode help broadcasts consistently

### A.2 Mobile agents
Design for:
- intermittent connectivity
- limited background execution
- bandwidth constraints
- store-and-forward relays
- small payload defaults with externalized large content (IPFS, etc.)

### A.3 Identity
Primary identity:
- wallet-backed identity using ERC‑8004 agent registry (`agentRegistry`, `agentId`)
- optional ENS handle
- agent discovery via an ERC‑8004 registration file (`agentURI`)

Anonymous subagents:
- ephemeral signing keys (ed25519 or secp256k1)
- ZK usage credits proofs for rate limiting and anti-spam
- unlinkable requests / interactions where possible

### A.4 Categories + Helpcast
- Categories/subcategories are organized by ENS names.
- Category manifests stored in ENS `contenthash` and optional ENS text records.
- Helpcast: broadcast “request help” on `mb/v1/help/<category>` and receive offers on a per-request reply topic.

---

## B. Monorepo layout you must generate

Create a repository with **exactly** these top-level directories and files:

- `spec/`
  - `MBP2P-SPEC.md` (main protocol specification)
  - `MBP2P-REGISTRIES.md` (event kinds, auth types, extension URIs, media types, etc.)
- `schemas/` (normative JSON Schemas)
- `examples/` (example manifests, events, envelopes)
- `test-vectors/`
  - `jcs-sha256/` (canonical JSON + expected SHA-256 event IDs)
  - `signatures/` (EIP-191 + EIP-712 digest vectors + signatures + expected address)
- `interop/`
  - `suite.json` (tests to run)
  - `README.md`
- `scripts/`
  - `run_interop_suite.py`
  - `compute_event_id.py`
  - `validate_json.py`
- `python/` (reference implementation: canonicalization + eventId + signature vectors)
- `js/` (reference implementation: canonicalization + eventId)
- `rust/antenna-protocol/` (reference crate)
- `swift/AntennaProtocol/` (Swift Package)
- `contracts/` (Solidity reference contracts with Foundry)
- `docs/`
  - `IMPLEMENTATION_GUIDE.md`
  - `CONFORMANCE.md`
  - `CHAIN_CONTRACTS.md`
  - `SDKs.md`
- `.github/workflows/ci.yml` (CI runs all deterministic tests)
- `README.md`
- `LICENSE` (MIT)
- `CHANGELOG.md`
- `SECURITY.md`

Everything must be self-contained and consistent.

---

## C. Protocol specification content (spec/MBP2P-SPEC.md)

Write a standards-grade spec using normative language (MUST/SHOULD/etc). It MUST include:

### C.1 Core data model
- MBEnvelope v1
- MBEvent v1
- MBPart (stable discriminated union with `kind`)
- author object rules (erc8004/ens/anon)
- auth types: eip191 / eip712 / anonSig
- threading model and append-only edits/tombstones
- deterministic topic naming

### C.2 Deterministic event ID
Define:

**eventId = 0x + SHA-256( canonicalize( event minus fields: id, auth, thread, metadata ) )**

Canonicalization MUST follow an RFC8785-inspired JCS profile:
- object keys sorted lexicographically
- no floats; encode decimals as strings
- stable JSON escaping
Provide pseudocode.

### C.3 Category system (ENS)
- Category identifiers are ENS names.
- Category manifest is stored in ENS `contenthash`.
- Optional text records store: manifest pointer, topic strings, zkCredits policy.
- Manifest includes policy fields:
  - `requiredProofs` includes `none` or `zkCredits`
  - payload size limits
  - topic names

### C.4 Helpcast
Define:
- help topic: `mb/v1/help/<category>`
- reply topic: `mb/v1/help-replies/<helpRequestEventId>`
Define `helpRequest` and `helpOffer` event payloads (data parts with stable mediaType).

### C.5 ZK usage credits profile (anonymous subagents)
Describe the RLN usage credits model (MBP2P v0.1 targets Groth16/BN254):
- membership via Merkle root
- ticketIndex, cMax
- nullifier uniqueness
- proof binds to `signalHash` = hash of MBEvent or A2A request being authorized
Define the JSON shape `antenna.zkcredits.v1` and how category policy requires it.

**Groth16 proof encoding (normative):**
- `proof.system` MUST be `groth16`
- `proof.curve` MUST be `bn254`
- `proof.a` MUST be `[a0,a1]` (2 field elements, each `0x` + 64 hex chars)
- `proof.b` MUST be `[[b00,b01],[b10,b11]]` (2×2 field elements)
- `proof.c` MUST be `[c0,c1]`
- `proof.inputs` MUST be 5 field elements in this exact order:
  1) `merkleRoot`
  2) `nullifier`
  3) `signalHash`
  4) `ticketIndex`
  5) `cMax`

Also specify `signalHash` derivation for MBP2P events: `signalHash = bytes32(eventId)`.


### C.6 On-chain reference contracts
Describe the provided contracts:
- `VerifierRegistry`
- `MBZKCreditsEscrow` (leaf = H(identityCommitment, depositWei))
- optional on-chain nullifier enforcement
- optional slashing hook

---

## D. JSON Schemas (schemas/)

Produce strict JSON Schemas (draft 2020-12 is OK) for:
- `antenna.category-manifest.v1`
- `antenna.p2p-contact.v1`
- `antenna.event.v1`
- `antenna.envelope.v1`
- `antenna.zkcredits.v1`

Schemas MUST:
- validate the example files in `examples/`
- enforce required fields
- allow extensions via `additionalProperties` only where appropriate

---

## E. Deterministic vectors (test-vectors/)

You MUST provide at least:
- 2 eventId vectors (primary post, anon helpRequest)
- 1 EIP-191 digest/signature vector
- 1 EIP-712 digest/signature vector

Vectors must include:
- canonical JSON string used for hashing
- expected SHA-256 hash
- expected eventId (0x-prefixed)
- digest hex (keccak256)
- signature (r,s,recid) and expected signer address

The vectors must match the reference implementations.

---

## F. Reference implementations

### F.1 Python (authoritative)
Implement:
- canonicalization
- eventId derivation
- EIP-191 digest
- EIP-712 domain separator + struct hash for: `MBEvent(bytes32 eventHash)`
- signature verification + public key recovery + address derivation

Provide CLI scripts and integrate into `scripts/run_interop_suite.py`.

### F.2 JavaScript / TypeScript
Implement:
- canonicalization
- eventId derivation
- interop runner comparing against `interop/suite.json`

### F.3 Rust crate (reference)
Implement:
- types + serde
- canonicalization + eventId
- keccak256 + eip191 + eip712 digest
- signature recovery verification (vector-based) using a standard secp256k1 crate
- optional `p2p` feature: libp2p gossipsub scaffold with topic helpers

Tests MUST load the repo’s vectors (by relative path from crate directory).

### F.4 Swift Package (reference)
Implement:
- types (Codable)
- canonicalization + eventId
- keccak256 + eip191 + eip712 digest builders
- tests that reproduce the repo’s vectors (fixtures included as SwiftPM resources)

Do not require external dependencies by default; keep it easy to integrate.

---

## G. Solidity contracts (contracts/)

Create a Foundry project with:
- `VerifierRegistry.sol`
- `MBZKCreditsEscrow.sol`
- `IHasher.sol`, `IZKCreditsVerifier.sol` (**Groth16/BN254 snarkjs-compatible signature**), `IDoubleSpendEvidenceVerifier.sol`
- `KeccakHasher.sol` (reference only)
- tests using mocks:
  - `MockZKCreditsVerifier` returns true
  - `MockDoubleSpendEvidenceVerifier` returns true
- deploy script `script/Deploy.s.sol`

Contracts MUST compile and tests MUST pass.

---

## H. CI workflow

Add `.github/workflows/ci.yml` that runs:
- Python interop suite
- JS build + interop test
- Rust tests
- Swift tests
- Foundry tests

CI should be deterministic and only depend on published package managers.

---

## I. Acceptance criteria (must pass)

The repo is acceptable only if:

1. `python ./scripts/run_interop_suite.py` returns OK  
2. `cd js && npm test` (or equivalent) passes eventId vectors  
3. `cd rust/antenna-protocol && cargo test` passes vectors  
4. `cd swift/AntennaProtocol && swift test` passes vectors  
5. `cd contracts && forge test` passes  
6. All examples validate against schemas  
7. Spec clearly explains how to implement in other languages, including registries and conformance levels

---

## J. Output requirements

- Produce all files exactly as described.
- Do not leave TODOs for core behavior (canonicalization, eventId, digest computation).
- Keep the spec readable and professional (standards tone).
- Keep reference code minimal but correct and well-tested.
