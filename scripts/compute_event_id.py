#!/usr/bin/env python3
import json
import os
import sys

# Allow running without installing the package
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(REPO_ROOT, "python"))

from antenna_spec_tools.event_id import compute_event_id

def main():
    if len(sys.argv) != 2:
        print("Usage: compute_event_id.py <event.json>", file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        event = json.load(f)
    print(compute_event_id(event))

if __name__ == "__main__":
    main()
