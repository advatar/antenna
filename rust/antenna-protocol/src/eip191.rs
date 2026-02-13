use crate::error::MBP2PError;
use tiny_keccak::{Hasher, Keccak};

pub fn keccak256(data: &[u8]) -> [u8; 32] {
    let mut k = Keccak::v256();
    k.update(data);
    let mut out = [0u8; 32];
    k.finalize(&mut out);
    out
}

/// EIP-191 personal_sign digest over a message.
///
/// digest = keccak256("\x19Ethereum Signed Message:\n" + len(message) + message)
pub fn eip191_digest(message: &[u8]) -> [u8; 32] {
    let prefix = format!("\x19Ethereum Signed Message:\n{}", message.len());
    let mut data = Vec::with_capacity(prefix.len() + message.len());
    data.extend_from_slice(prefix.as_bytes());
    data.extend_from_slice(message);
    keccak256(&data)
}

pub fn eip191_digest_bytes32(bytes32: &[u8]) -> Result<[u8; 32], MBP2PError> {
    if bytes32.len() != 32 {
        return Err(MBP2PError::Crypto("bytes32 must be 32 bytes".into()));
    }
    Ok(eip191_digest(bytes32))
}
