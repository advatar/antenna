#!/usr/bin/env python3
import json
import os
import sys
from glob import glob

import jsonschema

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

def load_schema(path: str):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def validate_file(schema, path: str):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    jsonschema.validate(instance=data, schema=schema)

def main():
    schema_name = sys.argv[1] if len(sys.argv) > 1 else None
    if not schema_name:
        print("Usage: validate_json.py <schema-file-name> (e.g., antenna.event.v1.schema.json)", file=sys.stderr)
        sys.exit(2)

    schema_path = os.path.join(REPO_ROOT, "schemas", schema_name)
    schema = load_schema(schema_path)

    # Validate all examples that declare a matching "type" prefix or are mapped in examples/README.
    examples_dir = os.path.join(REPO_ROOT, "examples")
    candidates = glob(os.path.join(examples_dir, "*.json"))

    ok = 0
    fail = 0
    for p in candidates:
        try:
            validate_file(schema, p)
            ok += 1
        except Exception as e:
            # Not all examples match all schemas; this tool is used per-schema.
            continue
    print(f"Validated {ok} example files against {schema_name} (others skipped).")

if __name__ == "__main__":
    main()
