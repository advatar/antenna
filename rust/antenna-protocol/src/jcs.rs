use crate::error::MBP2PError;
use serde_json::Value;

/// Canonicalize a serde_json::Value into a deterministic JSON string.
///
/// Profile:
/// - Objects: keys sorted lexicographically
/// - Arrays: order preserved
/// - Strings: standard JSON escaping
/// - Numbers: integers only (no floats). If you need decimals, encode them as strings.
///
/// This follows the repository’s reference implementation (Python) closely.
pub fn canonicalize(value: &Value) -> Result<String, MBP2PError> {
    match value {
        Value::Null => Ok("null".to_string()),
        Value::Bool(b) => Ok(if *b { "true" } else { "false" }.to_string()),
        Value::String(s) => Ok(escape_string(s)),
        Value::Number(n) => {
            if let Some(i) = n.as_i64() {
                Ok(i.to_string())
            } else if let Some(u) = n.as_u64() {
                Ok(u.to_string())
            } else {
                Err(MBP2PError::UnsupportedNumber(n.to_string()))
            }
        }
        Value::Array(arr) => {
            let mut out = String::from("[");
            for (i, v) in arr.iter().enumerate() {
                if i > 0 { out.push(','); }
                out.push_str(&canonicalize(v)?);
            }
            out.push(']');
            Ok(out)
        }
        Value::Object(map) => {
            let mut keys: Vec<&String> = map.keys().collect();
            keys.sort();
            let mut out = String::from("{");
            for (i, k) in keys.iter().enumerate() {
                if i > 0 { out.push(','); }
                out.push_str(&escape_string(k));
                out.push(':');
                out.push_str(&canonicalize(&map[*k])?);
            }
            out.push('}');
            Ok(out)
        }
    }
}

fn escape_string(s: &str) -> String {
    // Use serde_json to escape correctly, but ensure no surrounding whitespace.
    serde_json::to_string(s).unwrap_or_else(|_| format!("\"{}\"", s.replace('"', "\\\"")))
}
