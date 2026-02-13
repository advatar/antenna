
/**
 * Antenna canonicalization profile (JCS-like).
 *
 * Interop constraints:
 * - No floats. Use integers or strings for decimals.
 * - Keys sorted lexicographically by Unicode code point.
 * - Minimal JSON escaping (control chars, quote, backslash).
 */

export type JsonValue =
  | null
  | boolean
  | number
  | string
  | JsonValue[]
  | { [k: string]: JsonValue };

function escapeString(s: string): string {
  let out = '"';
  for (const ch of s) {
    const code = ch.codePointAt(0)!;
    if (ch === '"') out += '\\"';
    else if (ch === "\\") out += "\\\\";
    else if (ch === "\b") out += "\\b";
    else if (ch === "\f") out += "\\f";
    else if (ch === "\n") out += "\\n";
    else if (ch === "\r") out += "\\r";
    else if (ch === "\t") out += "\\t";
    else if (code < 0x20) out += "\\u" + code.toString(16).padStart(4, "0");
    else out += ch;
  }
  out += '"';
  return out;
}

function canonicalizeNumber(x: number): string {
  if (!Number.isFinite(x)) {
    throw new Error("Non-finite numbers are not allowed");
  }
  if (!Number.isInteger(x)) {
    throw new Error("Floats are not allowed in canonicalization profile; encode decimals as strings");
  }
  return x.toString(10);
}

export function canonicalize(v: JsonValue): string {
  if (v === null) return "null";
  if (v === true) return "true";
  if (v === false) return "false";
  if (typeof v === "string") return escapeString(v);
  if (typeof v === "number") return canonicalizeNumber(v);
  if (Array.isArray(v)) return "[" + v.map(canonicalize).join(",") + "]";
  if (typeof v === "object") {
    const keys = Object.keys(v).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
    const parts = keys.map((k) => escapeString(k) + ":" + canonicalize((v as any)[k]));
    return "{" + parts.join(",") + "}";
  }
  throw new Error("Unsupported JSON type");
}
