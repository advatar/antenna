use antenna_protocol::{event_id, eip191, eip712};
use antenna_protocol::types::MBEvent;

use k256::ecdsa::{Signature, RecoveryId, VerifyingKey};
use k256::ecdsa::signature::hazmat::PrehashVerifier;

fn repo_path() -> std::path::PathBuf {
    // CARGO_MANIFEST_DIR = rust/antenna-protocol
    let mut p = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    p.pop(); // rust
    p.pop(); // repo root
    p
}

fn read_json(rel: &str) -> serde_json::Value {
    let path = repo_path().join(rel);
    let s = std::fs::read_to_string(&path).expect(&format!("read {}", path.display()));
    serde_json::from_str(&s).unwrap()
}

fn hex32(s: &str) -> [u8; 32] {
    let clean = s.trim_start_matches("0x");
    let bytes = hex::decode(clean).unwrap();
    let mut out = [0u8; 32];
    out.copy_from_slice(&bytes);
    out
}

fn eth_address_from_pubkey(vk: &VerifyingKey) -> String {
    let ep = vk.to_encoded_point(false);
    let bytes = ep.as_bytes();
    // bytes[0] is 0x04, then 64 bytes x||y
    let hash = eip191::keccak256(&bytes[1..]);
    let addr = &hash[12..32];
    format!("0x{}", hex::encode(addr))
}

#[test]
fn event_id_vectors() {
    let event_post: MBEvent = serde_json::from_value(read_json("examples/event.post.primary.json")).unwrap();
    let got = event_id::compute_event_id(&event_post).unwrap();
    assert_eq!(got.to_lowercase(), "0x3722033095f71954949abc38c48f392a9d18644084078cb710a87c8890f3eb01");

    let event_help: MBEvent = serde_json::from_value(read_json("examples/event.helprequest.anon.json")).unwrap();
    let got2 = event_id::compute_event_id(&event_help).unwrap();
    assert_eq!(got2.to_lowercase(), "0x29bf715be4959553f7e2c02ebfa47a39ef1d72bf130255a0d3e33217e1a155e2");
}

#[test]
fn eip191_digest_and_recover_vector1() {
    let v = read_json("test-vectors/signatures/eip191_vector1.json");
    let msg = hex32(v["messageBytes32"].as_str().unwrap());
    let digest = eip191::eip191_digest(&msg);
    assert_eq!(format!("0x{}", hex::encode(digest)), v["digestKeccak256"].as_str().unwrap().to_lowercase());

    let r = hex::decode(v["signature"]["r"].as_str().unwrap().trim_start_matches("0x")).unwrap();
    let s = hex::decode(v["signature"]["s"].as_str().unwrap().trim_start_matches("0x")).unwrap();
    let recid_u8 = v["signature"]["recid"].as_u64().unwrap() as u8;

    let mut rs = [0u8; 64];
    rs[..32].copy_from_slice(&r);
    rs[32..].copy_from_slice(&s);
    let sig = Signature::from_bytes((&rs).into()).unwrap();
    let recid = RecoveryId::try_from(recid_u8).unwrap();

    let vk = VerifyingKey::recover_from_prehash(&digest, &sig, recid).unwrap();
    let addr = eth_address_from_pubkey(&vk);
    assert_eq!(addr.to_lowercase(), v["expectedSignerAddress"].as_str().unwrap().to_lowercase());

    // Verify signature against digest
    vk.verify_prehash(&digest, &sig).unwrap();
}

#[test]
fn eip712_digest_and_recover_vector1() {
    let v = read_json("test-vectors/signatures/eip712_vector1.json");
    let event_hash = hex32(v["eventHashBytes32"].as_str().unwrap());

    let verifying_contract = eip712::parse_address(v["domain"]["verifyingContract"].as_str().unwrap()).unwrap();
    let domain = eip712::Domain {
        name: v["domain"]["name"].as_str().unwrap().to_string(),
        version: v["domain"]["version"].as_str().unwrap().to_string(),
        chain_id: v["domain"]["chainId"].as_u64().unwrap(),
        verifying_contract,
    };

    let domain_sep = eip712::domain_separator(&domain);
    assert_eq!(format!("0x{}", hex::encode(domain_sep)), v["domainSeparator"].as_str().unwrap().to_lowercase());

    let struct_hash = eip712::struct_hash_mbevent(&event_hash);
    assert_eq!(format!("0x{}", hex::encode(struct_hash)), v["structHash"].as_str().unwrap().to_lowercase());

    let digest = eip712::digest(&domain_sep, &struct_hash);
    assert_eq!(format!("0x{}", hex::encode(digest)), v["digestKeccak256"].as_str().unwrap().to_lowercase());

    let r = hex::decode(v["signature"]["r"].as_str().unwrap().trim_start_matches("0x")).unwrap();
    let s = hex::decode(v["signature"]["s"].as_str().unwrap().trim_start_matches("0x")).unwrap();
    let recid_u8 = v["signature"]["recid"].as_u64().unwrap() as u8;

    let mut rs = [0u8; 64];
    rs[..32].copy_from_slice(&r);
    rs[32..].copy_from_slice(&s);
    let sig = Signature::from_bytes((&rs).into()).unwrap();
    let recid = RecoveryId::try_from(recid_u8).unwrap();

    let vk = VerifyingKey::recover_from_prehash(&digest, &sig, recid).unwrap();
    let addr = eth_address_from_pubkey(&vk);
    assert_eq!(addr.to_lowercase(), v["expectedSignerAddress"].as_str().unwrap().to_lowercase());

    vk.verify_prehash(&digest, &sig).unwrap();
}
