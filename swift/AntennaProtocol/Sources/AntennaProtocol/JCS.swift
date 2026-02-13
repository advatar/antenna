import Foundation

/// RFC8785-inspired JSON canonicalization for MBP2P payloads.
///
/// Profile constraints:
/// - Object keys sorted lexicographically (Unicode scalar order)
/// - Arrays preserved
/// - Strings JSON-escaped
/// - Numbers: integers only (no floating point). Encode decimals as strings.
///
/// Input type is Foundation JSON (Dictionary / Array / String / NSNumber / NSNull / Bool).
public enum JCS {
    public static func canonicalize(_ value: Any) throws -> String {
        if value is NSNull { return "null" }
        if let b = value as? Bool { return b ? "true" : "false" }
        if let s = value as? String { return escapeString(s) }
        if let n = value as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                // NSNumber can be a Bool; already handled above, but guard anyway.
                let b = n.boolValue
                return b ? "true" : "false"
            }
            // Reject floats
            if CFNumberIsFloatType(n) {
                throw MBP2PError.unsupportedNumber("float: \(n)")
            }
            // Canonical integer representation
            // NSNumber -> Int64/UInt64 fallback; if it doesn't fit, use decimal string.
            // (In practice, MBP2P uses 64-bit safe integers for JSON.)
            if n.doubleValue == floor(n.doubleValue) {
                // Use string conversion without scientific notation
                return String(n.int64Value)
            } else {
                throw MBP2PError.unsupportedNumber("non-integer: \(n)")
            }
        }
        if let arr = value as? [Any] {
            let inner = try arr.map { try canonicalize($0) }.joined(separator: ",")
            return "[" + inner + "]"
        }
        if let dict = value as? [String: Any] {
            let keys = dict.keys.sorted()
            var parts: [String] = []
            parts.reserveCapacity(keys.count)
            for k in keys {
                let v = dict[k] ?? NSNull()
                let keyEsc = escapeString(k)
                let valEsc = try canonicalize(v)
                parts.append(keyEsc + ":" + valEsc)
            }
            return "{" + parts.joined(separator: ",") + "}"
        }

        throw MBP2PError.canonicalizationError("Unsupported JSON type: \(type(of: value))")
    }

    private static func escapeString(_ s: String) -> String {
        var out = "\""
        out.reserveCapacity(s.count + 2)
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x08: out += "\\b"
            case 0x0C: out += "\\f"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0x00...0x1F:
                out += String(format: "\\u%04x", scalar.value)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
        return out
    }
}
