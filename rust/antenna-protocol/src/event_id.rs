use crate::{error::MBP2PError, jcs, types::MBEvent};
use serde_json::Value;
use sha2::{Digest, Sha256};

/// Fields excluded from eventId hashing per MBP2P v0.1.0.
pub const STRIP_FIELDS: [&str; 4] = ["id", "auth", "thread", "metadata"];

/// Compute event.id = 0x + SHA-256( canonicalize(event without id/auth/thread/metadata) )
pub fn compute_event_id(event: &MBEvent) -> Result<String, MBP2PError> {
    let mut v = serde_json::to_value(event).map_err(|e| MBP2PError::InvalidJson(e.to_string()))?;
    strip_fields(&mut v)?;
    let canon = jcs::canonicalize(&v)?;
    let digest = Sha256::digest(canon.as_bytes());
    Ok(format!("0x{}", hex::encode(digest)))
}

fn strip_fields(v: &mut Value) -> Result<(), MBP2PError> {
    let obj = v.as_object_mut().ok_or_else(|| MBP2PError::InvalidJson("event must be object".into()))?;
    for k in STRIP_FIELDS {
        obj.remove(k);
    }
    Ok(())
}
