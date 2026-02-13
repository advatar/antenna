use crate::error::MBP2PError;
use crate::eip191::keccak256;

/// Matches the repository interop vectors:
/// - domain type: EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)
/// - struct type: MBEvent(bytes32 eventHash)
pub const DOMAIN_TYPE: &str = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";
pub const EVENT_TYPE: &str = "MBEvent(bytes32 eventHash)";

#[derive(Debug, Clone)]
pub struct Domain {
    pub name: String,
    pub version: String,
    pub chain_id: u64,
    pub verifying_contract: [u8; 20],
}

fn abi_encode_uint256(x: u64) -> [u8; 32] {
    let mut out = [0u8; 32];
    out[24..32].copy_from_slice(&x.to_be_bytes());
    out
}

fn abi_encode_address(addr20: &[u8; 20]) -> [u8; 32] {
    let mut out = [0u8; 32];
    out[12..32].copy_from_slice(addr20);
    out
}

fn abi_encode_bytes32(b32: &[u8; 32]) -> [u8; 32] { *b32 }

fn abi_encode_string_hash(s: &str) -> [u8; 32] { keccak256(s.as_bytes()) }

pub fn domain_separator(domain: &Domain) -> [u8; 32] {
    let type_hash = keccak256(DOMAIN_TYPE.as_bytes());
    let name_hash = abi_encode_string_hash(&domain.name);
    let version_hash = abi_encode_string_hash(&domain.version);

    let mut enc = Vec::with_capacity(32 * 5);
    enc.extend_from_slice(&type_hash);
    enc.extend_from_slice(&abi_encode_bytes32(&name_hash));
    enc.extend_from_slice(&abi_encode_bytes32(&version_hash));
    enc.extend_from_slice(&abi_encode_uint256(domain.chain_id));
    enc.extend_from_slice(&abi_encode_address(&domain.verifying_contract));

    keccak256(&enc)
}

pub fn struct_hash_mbevent(event_hash: &[u8; 32]) -> [u8; 32] {
    let type_hash = keccak256(EVENT_TYPE.as_bytes());

    let mut enc = Vec::with_capacity(64);
    enc.extend_from_slice(&type_hash);
    enc.extend_from_slice(event_hash);
    keccak256(&enc)
}

pub fn digest(domain_sep: &[u8; 32], struct_hash: &[u8; 32]) -> [u8; 32] {
    let mut data = Vec::with_capacity(2 + 32 + 32);
    data.push(0x19);
    data.push(0x01);
    data.extend_from_slice(domain_sep);
    data.extend_from_slice(struct_hash);
    keccak256(&data)
}

pub fn parse_address(hex_addr: &str) -> Result<[u8; 20], MBP2PError> {
    let clean = hex_addr.trim_start_matches("0x");
    let bytes = hex::decode(clean).map_err(|e| MBP2PError::Hex(e.to_string()))?;
    if bytes.len() != 20 {
        return Err(MBP2PError::Hex("address must be 20 bytes".into()));
    }
    let mut out = [0u8; 20];
    out.copy_from_slice(&bytes);
    Ok(out)
}
