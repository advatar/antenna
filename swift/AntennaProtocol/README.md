# AntennaProtocol (Swift Package)

Reference Swift implementation of the **MBP2P** protocol primitives for iOS/macOS agents:

- MBP2P data types (`Event`, `Envelope`, `CategoryManifest`, `ZKCredits`, etc.)
- RFC8785-style canonicalization (JCS profile)
- `eventId` computation: `0x` + SHA-256(canonicalized(event minus id/auth/thread/metadata))
- Topic naming helpers (`mb/v1/cat/...`, `mb/v1/help/...`)
- EIP-191 and EIP-712 digest builders (wallet signing integration points)

> **Note:** This package does **not** ship a full Ethereum wallet stack. It outputs the exact bytes/digests
> you need to sign with your preferred signer (local key, Secure Enclave-backed key, WalletConnect, etc.)

## Usage

```swift
import AntennaProtocol

let event = try MBEvent.fromJSON(data: jsonData)
let eventId = try event.computeEventId()
```

## Tests

The test target includes eventId vectors aligned with the repository’s canonical vectors.

```bash
swift test
```
