
"""
RFC 8785 (JCS) - JSON Canonicalization Scheme

This module implements a practical, interoperable subset suitable for Antenna
test vectors and production payloads that avoid floating point numbers.

Design constraints (recommended by this repository):
- All numeric fields SHOULD be integers. If you need decimals, encode them as strings.
- No NaN/Infinity.
- All JSON must be UTF-8.

Canonicalization rules implemented:
- Objects: keys sorted lexicographically by Unicode code point
- Arrays: order preserved
- Strings: JSON-escaped as required by RFC 8259 (control chars, quote, backslash)
- Numbers: integers and Decimals supported; floats are rejected by default
"""

from __future__ import annotations

import json
from decimal import Decimal
from typing import Any

def _escape_string(s: str) -> str:
    out = ['"']
    for ch in s:
        code = ord(ch)
        if ch == '"':
            out.append('\\"')
        elif ch == '\\':
            out.append('\\\\')
        elif ch == '\b':
            out.append('\\b')
        elif ch == '\f':
            out.append('\\f')
        elif ch == '\n':
            out.append('\\n')
        elif ch == '\r':
            out.append('\\r')
        elif ch == '\t':
            out.append('\\t')
        elif code < 0x20:
            out.append('\\u%04x' % code)
        else:
            out.append(ch)
    out.append('"')
    return ''.join(out)

def _canonicalize_number(x: Any) -> str:
    # Integers are canonicalized as a base-10 string without leading zeros.
    if isinstance(x, bool):
        raise TypeError("bool is not a number")
    if isinstance(x, int):
        return str(x)
    if isinstance(x, Decimal):
        # RFC8785 allows decimals, but you must ensure no exponent form if you want stable output.
        # We normalize to a plain string (no exponent) where possible.
        t = format(x, 'f')
        # strip trailing zeros and dot if needed
        if '.' in t:
            t = t.rstrip('0').rstrip('.')
        if t == '-0':
            t = '0'
        return t
    if isinstance(x, float):
        raise TypeError("float not supported for canonicalization in this profile; encode decimals as strings")
    raise TypeError(f"Unsupported number type: {type(x)}")

def canonicalize(value: Any) -> str:
    """
    Canonicalize a Python JSON structure into a canonical JSON string.

    Raises TypeError on unsupported types (notably float).
    """
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, str):
        return _escape_string(value)
    if isinstance(value, (int, Decimal)) and not isinstance(value, bool):
        return _canonicalize_number(value)
    if isinstance(value, list):
        return "[" + ",".join(canonicalize(v) for v in value) + "]"
    if isinstance(value, dict):
        # keys MUST be strings in JSON
        items = []
        for k in sorted(value.keys(), key=lambda x: x):
            if not isinstance(k, str):
                raise TypeError("JSON object keys must be strings")
            items.append(_escape_string(k) + ":" + canonicalize(value[k]))
        return "{" + ",".join(items) + "}"
    # Disallow bytes; encode as base64 string upstream
    raise TypeError(f"Unsupported JSON type: {type(value)}")

def canonicalize_json_text(json_text: str) -> str:
    """
    Convenience: parse then canonicalize.
    Uses Decimal for floats if present, but will raise unless you allow Decimal in your payload.
    """
    obj = json.loads(json_text, parse_float=Decimal)
    return canonicalize(obj)
