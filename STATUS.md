# STATUS

## 2026-02-17
- [x] Add one-command relay deployment script for `ground.zerok.cloud` (SSH sync, remote build, systemd service, reverse proxy wiring).

## 2026-02-14
- [x] Add decentralized relay + discovery implementation in Rust (deployable service with bootstrap list, gossip peer discovery, and relay fallback behavior).
- [x] Add Swift `AntennaProtocol` relay client helpers for multi-relay bootstrap/discovery/fallback publishing.
- [x] Integrate Clawdex/mac peer-assist publish path with the new Antenna relay discovery and fallback flow.

## 2026-02-13
- [x] Rebrand protocol references from the legacy name to Antenna across docs and source code.
- [x] Rename old-name package/module/schema paths to Antenna equivalents.
- [x] Run validation checks and confirm no remaining old-name references.
- [x] Commit and push changes.
