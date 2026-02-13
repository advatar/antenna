
# antenna-spec-tools (Python)

Reference implementation pieces for:
- RFC8785-ish canonicalization profile (no floats)
- Antenna event ID computation
- secp256k1 ECDSA signing/verification + EIP-191 and minimal EIP-712 digests
- Interop suite runner

## Install (editable)

```bash
pip install -e ./python
```

## Run interop suite

```bash
python ./scripts/run_interop_suite.py
```

## Compute an event id

```bash
python ./scripts/compute_event_id.py examples/event.post.primary.json
```
