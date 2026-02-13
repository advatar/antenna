
# Interop Suite

The repository includes a deterministic interoperability suite to help two independent
implementations converge on:

- canonicalization + eventId computation
- basic schema conformance
- EIP-191 and minimal EIP-712 digests/signatures

## Run (Python)

```bash
pip install -e ./python
python ./scripts/run_interop_suite.py
```

## Run (JavaScript)

JS reference currently checks **eventId** vectors only.

```bash
cd js
npm install
npm run build
npm run test:interop
```

## What it *does not* test (yet)

- ERC-8004 ownership/operator authorization checks
- ENS resolution correctness (depends on RPC + resolver libraries)
- ZK credits proof verification (depends on verifier choice + circuit keys)
- Transport-level behavior (pubsub / libp2p / WebRTC)
