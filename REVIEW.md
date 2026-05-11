# Code Review: Antenna

Review date: 2026-05-11
Tracker: https://github.com/advatar/Tracker/issues/53
Scope: top-level app folder `Antenna` and nested project manifests under this folder, excluding generated dependency/build directories such as `.git`, `node_modules`, `target`, `.build`, `dist`, and virtual environments.

## Executive Summary

- Overall risk from this sweep: **Medium**
- Findings by severity: High 0, Medium 2, Low 0
- Source footprint: 48 source files by extension scan (Swift 14, Rust 12, Solidity 11, Python 7, TypeScript 3, Shell 1)
- Test footprint: 9 test-like files detected
- CI footprint: 1 GitHub Actions workflow files detected
- Git posture: 2 changed/untracked paths before review generation
- Pattern scan budget used: 105 text/source files scanned

## Architecture Snapshot

Detected project and build surfaces:
- `js/package-lock.json`
- `js/package.json`
- `python/pyproject.toml`
- `python/requirements.txt`
- `rust/antenna-protocol/Cargo.toml`
- `rust/antenna-relay/Cargo.toml`
- `swift/AntennaProtocol/Package.swift`

Nested manifest owners sampled:
- `js`
- `python`
- `rust/antenna-protocol`
- `rust/antenna-relay`
- `swift/AntennaProtocol`

Package scripts sampled:
- ``js/package.json`: build, test:interop`

Local instruction/status files:
- `AGENTS.md`
- `STATUS.md`

## Findings

### 1. [Medium] Potential credential/config material needs a focused secret audit

Names commonly used for credentials or sensitive tokens appear in app-owned files. Some hits may be fixtures or placeholders, but every example should be verified, documented as fake, or moved to secret management. Values are redacted here. Scanner count: 8.

Evidence:
- contracts/script/Deploy.s.sol:19 `uint256 deployerKey = vm.envUint("PRIVATE_KEY");`
- contracts/src/MBZKCreditsEscrow.sol:31 `// The "ID" in the usage-credits design: typically Hash(secret_k)`
- contracts/src/interfaces/IDoubleSpendEvidenceVerifier.sol:5 `/// @dev In RLN-style systems, double-signing with the same nullifier can allow recovering a secret.`
- contracts/test/MBZKCreditsEscrow.t.sol:35 `bytes32 id = keccak256("alice-secret");`
- contracts/test/MBZKCreditsEscrow.t.sol:57 `bytes32 id = keccak256("bob-secret");`
- schemas/antenna.category-manifest.v1.schema.json:158 `"token"`
- test-vectors/signatures/eip191_vector1.json:4 `"privateKey": "0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",`
- test-vectors/signatures/eip712_vector1.json:4 `"privateKey": "0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",`
### 2. [Medium] Runtime failure shortcuts are common enough to deserve hardening

Force unwraps, panics, unwraps, expect calls, and fatal errors should be converted to typed errors around IO, persistence, parsing, and user-driven paths. Scanner count: 33.

Evidence:
- rust/antenna-protocol/tests/interop_vectors.rs:17 `let s = std::fs::read_to_string(&path).expect(&format!("read {}", path.display()));`
- rust/antenna-protocol/tests/interop_vectors.rs:18 `serde_json::from_str(&s).unwrap()`
- rust/antenna-protocol/tests/interop_vectors.rs:23 `let bytes = hex::decode(clean).unwrap();`
- rust/antenna-protocol/tests/interop_vectors.rs:40 `let event_post: MBEvent = serde_json::from_value(read_json("examples/event.post.primary.json")).unwrap();`
- rust/antenna-protocol/tests/interop_vectors.rs:41 `let got = event_id::compute_event_id(&event_post).unwrap();`
- rust/antenna-protocol/tests/interop_vectors.rs:44 `let event_help: MBEvent = serde_json::from_value(read_json("examples/event.helprequest.anon.json")).unwrap();`
- rust/antenna-protocol/tests/interop_vectors.rs:45 `let got2 = event_id::compute_event_id(&event_help).unwrap();`
- rust/antenna-protocol/tests/interop_vectors.rs:52 `let msg = hex32(v["messageBytes32"].as_str().unwrap());`

## Testing and Build Posture

Detected tests:
- `contracts/test/MBZKCreditsEscrow.t.sol`
- `rust/antenna-protocol/tests/interop_vectors.rs`
- `spec/MBP2P-REGISTRIES.md`
- `spec/MBP2P-SPEC.md`
- `swift/AntennaProtocol/Tests/AntennaProtocolTests/DigestVectorsTests.swift`
- `swift/AntennaProtocol/Tests/AntennaProtocolTests/EventIdVectorsTests.swift`
- `swift/AntennaProtocol/Tests/AntennaProtocolTests/Fixtures/event.helprequest.anon.json`
- `swift/AntennaProtocol/Tests/AntennaProtocolTests/Fixtures/event.post.primary.json`
- `swift/AntennaProtocol/Tests/AntennaProtocolTests/RelayClientTests.swift`

Detected CI workflows:
- `.github/workflows/ci.yml`

Inferred verification commands to standardize:
- JavaScript: run the owning package-manager install/build/test scripts from the relevant `package.json`.
- Rust: run `cargo test` or workspace-specific checks from each Cargo workspace root.
- Python: run the project pytest/ruff/mypy commands declared in `pyproject.toml` or CI.
- Swift Package: run `swift test` from each package root.

## Review Limitations

- This was a broad static review across many local apps, not a full manual product walkthrough.
- Generated directories and dependency trees were pruned so findings focus on app-owned source.
- Secret-like values were not reproduced; examples are redacted or limited to path/line evidence.
- Pattern scanning is capped per app to keep the cross-repository sweep tractable; high-risk folders need focused follow-up review.

## Recommended Next Steps

1. Resolve every High finding first, especially secret material, tracked generated output, and dynamic execution paths.
2. Add or tighten the app's canonical CI workflow so build and tests run on every push.
3. Convert inferred build/test commands into documented commands in the app README or STATUS file.
4. Add smoke tests around app launch, persistence, API boundaries, and security-sensitive adapters.
5. Re-run this review after cleanup and replace this file with a human-reviewed release checklist.
