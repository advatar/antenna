# Reference SDKs

This repository ships reference implementations in multiple languages to make interoperability practical.

## Swift Package
Path: `swift/AntennaProtocol`

Core deliverables:
- `MBEvent`, `MBEnvelope`, parts/authors/auth
- RFC8785-style canonicalization (restricted)
- `eventId` computation
- Keccak-256 + EIP-191 + EIP-712 digest builders
- test vectors

Integrators should combine this package with:
- an Ethereum signing stack (local key, WalletConnect, etc.)
- an ENS resolver client / RPC provider
- a P2P transport implementation (libp2p/webrtc/relay)

## Rust crate
Path: `rust/antenna-protocol`

Core deliverables:
- MBP2P types + serde support
- canonicalization + eventId
- Keccak-256 + EIP-191 + EIP-712 digests
- signature recovery vectors (via k256)
- optional `p2p` feature (libp2p scaffolding)

## Python + JS
The existing `python/` and `js/` packages remain normative references for:
- canonicalization and eventId vectors
- signature vectors and recovery logic (Python)
