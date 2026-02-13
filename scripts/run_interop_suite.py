#!/usr/bin/env python3
import json
import os
import sys
from typing import Any, Dict, List

import jsonschema

# Allow running without installing the package
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(REPO_ROOT, "python"))

def load_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def main():
    suite_path = os.path.join(REPO_ROOT, "interop", "suite.json")
    suite = load_json(suite_path)

    schemas_cache: Dict[str, Any] = {}

    def get_schema(schema_file: str) -> Any:
        if schema_file not in schemas_cache:
            schemas_cache[schema_file] = load_json(os.path.join(REPO_ROOT, "schemas", schema_file))
        return schemas_cache[schema_file]

    failures: List[str] = []

    # --- Schema validation ---
    for test in suite.get("schemaValidation", []):
        schema = get_schema(test["schema"])
        data = load_json(os.path.join(REPO_ROOT, test["file"]))
        try:
            jsonschema.validate(instance=data, schema=schema)
        except Exception as e:
            failures.append(f"[schema] {test['name']}: {e}")

    # --- Event ID vectors ---
    from antenna_spec_tools.event_id import compute_event_id
    for vec in suite.get("eventIdVectors", []):
        event = load_json(os.path.join(REPO_ROOT, vec["eventFile"]))
        expected = vec["expectedEventId"]
        got = compute_event_id(event)
        if got != expected:
            failures.append(f"[eventId] {vec['name']}: expected {expected}, got {got}")

    # --- Signature vectors (EIP-191 / EIP-712) ---
    from antenna_spec_tools.secp256k1 import (
        recover_pubkey, pubkey_to_eth_address,
        eip191_digest, eip712_domain_separator, eip712_struct_hash_mbevent, eip712_digest,
        ecdsa_verify,
    )

    def b32(hexstr: str) -> bytes:
        h = hexstr[2:] if hexstr.startswith("0x") else hexstr
        return bytes.fromhex(h)

    for vec in suite.get("signatureVectors", []):
        if vec["kind"] == "eip191":
            msg = b32(vec["messageBytes32"])
            digest = eip191_digest(msg)
            expected_digest = vec.get("digestKeccak256")
        elif vec["kind"] == "eip712":
            event_hash = b32(vec["eventHashBytes32"])
            domain = eip712_domain_separator(
                vec["domain"]["name"],
                vec["domain"]["version"],
                int(vec["domain"]["chainId"]),
                vec["domain"]["verifyingContract"],
            )
            struct_hash = eip712_struct_hash_mbevent(event_hash)
            digest = eip712_digest(domain, struct_hash)
            expected_digest = vec.get("digestKeccak256")
        else:
            failures.append(f"[sig] {vec['name']}: unknown kind {vec['kind']}")
            continue

        if expected_digest and ("0x" + digest.hex()).lower() != expected_digest.lower():
            failures.append(f"[sig] {vec['name']}: digest mismatch")

        r = int(vec["signature"]["r"], 16)
        s = int(vec["signature"]["s"], 16)
        recid = int(vec["signature"]["recid"])
        pub = recover_pubkey(digest, r, s, recid)
        if pub is None:
            failures.append(f"[sig] {vec['name']}: pubkey recovery failed")
            continue
        addr = pubkey_to_eth_address(pub)
        if addr.lower() != vec["expectedSignerAddress"].lower():
            failures.append(f"[sig] {vec['name']}: expected addr {vec['expectedSignerAddress']}, got {addr}")

        if not ecdsa_verify(digest, r, s, pub):
            failures.append(f"[sig] {vec['name']}: signature verification failed")

    if failures:
        print("FAIL")
        for f in failures:
            print(" -", f)
        sys.exit(1)
    print("OK: schema validation, eventId, and signature vectors all passed.")

if __name__ == "__main__":
    main()
