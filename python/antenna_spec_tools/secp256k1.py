
from __future__ import annotations

import hashlib
import hmac
from dataclasses import dataclass
from typing import Optional, Tuple

from Crypto.Hash import keccak

# --- Keccak ---
def keccak256(data: bytes) -> bytes:
    k = keccak.new(digest_bits=256)
    k.update(data)
    return k.digest()

# --- secp256k1 domain parameters ---
P  = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
A  = 0
B  = 7
N  = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
Gx = 55066263022277343669578718895168534326250603453777594175500187360389116729240
Gy = 32670510020758816978083085130507043184471273380659243275938904335757337482424

def mod_inv(x: int, m: int) -> int:
    return pow(x, m - 2, m)

@dataclass(frozen=True)
class Point:
    x: int
    y: int

INF: Optional[Point] = None

def is_on_curve(Pt: Optional[Point]) -> bool:
    if Pt is None:
        return True
    x, y = Pt.x, Pt.y
    return (y * y - (x * x * x + A * x + B)) % P == 0

def point_neg(Pt: Optional[Point]) -> Optional[Point]:
    if Pt is None:
        return None
    return Point(Pt.x, (-Pt.y) % P)

def point_add(P1: Optional[Point], P2: Optional[Point]) -> Optional[Point]:
    if P1 is None:
        return P2
    if P2 is None:
        return P1
    if P1.x == P2.x and (P1.y != P2.y or P1.y == 0):
        return None

    if P1.x == P2.x:
        # point doubling
        lam = (3 * P1.x * P1.x + A) * mod_inv(2 * P1.y % P, P) % P
    else:
        lam = (P2.y - P1.y) * mod_inv((P2.x - P1.x) % P, P) % P

    x3 = (lam * lam - P1.x - P2.x) % P
    y3 = (lam * (P1.x - x3) - P1.y) % P
    return Point(x3, y3)

def scalar_mult(k: int, Pt: Optional[Point]) -> Optional[Point]:
    if k % N == 0 or Pt is None:
        return None
    if k < 0:
        return scalar_mult(-k, point_neg(Pt))
    result = None
    addend = Pt
    while k:
        if k & 1:
            result = point_add(result, addend)
        addend = point_add(addend, addend)
        k >>= 1
    return result

G = Point(Gx, Gy)

# --- RFC6979 deterministic nonce generation (HMAC-SHA256) ---
def rfc6979_generate_k(privkey: int, msg_hash32: bytes) -> int:
    """
    Deterministic nonce generation for ECDSA over secp256k1 using RFC6979 (HMAC-SHA256).
    msg_hash32 is the message hash (32 bytes).
    """
    if len(msg_hash32) != 32:
        raise ValueError("msg_hash32 must be 32 bytes")

    x = privkey.to_bytes(32, "big")
    h1 = msg_hash32

    V = b"\x01" * 32
    K = b"\x00" * 32
    K = hmac.new(K, V + b"\x00" + x + h1, hashlib.sha256).digest()
    V = hmac.new(K, V, hashlib.sha256).digest()
    K = hmac.new(K, V + b"\x01" + x + h1, hashlib.sha256).digest()
    V = hmac.new(K, V, hashlib.sha256).digest()

    while True:
        V = hmac.new(K, V, hashlib.sha256).digest()
        k = int.from_bytes(V, "big")
        k = k % N
        if 1 <= k < N:
            return k
        K = hmac.new(K, V + b"\x00", hashlib.sha256).digest()
        V = hmac.new(K, V, hashlib.sha256).digest()

# --- ECDSA sign/verify + recovery ---
def ecdsa_sign(msg_hash32: bytes, privkey: int) -> Tuple[int, int, int]:
    """
    Returns (r, s, recid) with 'low-s' normalization.
    """
    if not (1 <= privkey < N):
        raise ValueError("Invalid private key")
    z = int.from_bytes(msg_hash32, "big")

    k = rfc6979_generate_k(privkey, msg_hash32)
    R = scalar_mult(k, G)
    if R is None:
        raise RuntimeError("Invalid R point")
    r = R.x % N
    if r == 0:
        raise RuntimeError("r == 0")
    kinv = mod_inv(k, N)
    s = (kinv * (z + r * privkey)) % N
    if s == 0:
        raise RuntimeError("s == 0")

    # Ethereum "low-s" rule
    recid = 0
    if R.y % 2 == 1:
        recid |= 1
    if R.x >= N:
        recid |= 2

    if s > N // 2:
        s = N - s
        # flipping s flips recovery parity bit
        recid ^= 1

    return r, s, recid

def ecdsa_verify(msg_hash32: bytes, r: int, s: int, pubkey: Point) -> bool:
    if not (1 <= r < N and 1 <= s < N):
        return False
    if not is_on_curve(pubkey):
        return False
    z = int.from_bytes(msg_hash32, "big")
    w = mod_inv(s, N)
    u1 = (z * w) % N
    u2 = (r * w) % N
    X = point_add(scalar_mult(u1, G), scalar_mult(u2, pubkey))
    if X is None:
        return False
    return (X.x % N) == r

def recover_pubkey(msg_hash32: bytes, r: int, s: int, recid: int) -> Optional[Point]:
    """
    Recover public key from ECDSA signature and message hash.
    recid in {0,1,2,3}.
    """
    if recid not in (0,1,2,3):
        return None
    if not (1 <= r < N and 1 <= s < N):
        return None

    z = int.from_bytes(msg_hash32, "big")

    # Compute x = r + jn where j in {0,1}
    j = recid >> 1
    x = r + j * N
    if x >= P:
        return None

    # Recover y from curve equation y^2 = x^3 + 7
    alpha = (pow(x, 3, P) + B) % P
    beta = pow(alpha, (P + 1) // 4, P)  # since P % 4 == 3

    y = beta if (beta % 2) == (recid & 1) else (P - beta)
    R = Point(x, y)
    if not is_on_curve(R):
        return None

    r_inv = mod_inv(r, N)
    # Q = r^{-1} (sR - zG)
    sR = scalar_mult(s, R)
    zG = scalar_mult(z % N, G)
    if sR is None or zG is None:
        return None
    Q = scalar_mult(r_inv, point_add(sR, point_neg(zG)))
    return Q

def privkey_to_pubkey(privkey: int) -> Point:
    Q = scalar_mult(privkey, G)
    if Q is None:
        raise ValueError("Invalid privkey")
    return Q

def pubkey_to_eth_address(pubkey: Point) -> str:
    """
    Ethereum address = last 20 bytes of keccak256(uncompressed_pubkey[1:]).
    """
    x = pubkey.x.to_bytes(32, "big")
    y = pubkey.y.to_bytes(32, "big")
    uncompressed = x + y  # 64 bytes (no 0x04 prefix)
    addr = keccak256(uncompressed)[-20:]
    return "0x" + addr.hex()

# --- EIP-191 personal_sign (bytes) ---
def eip191_digest(msg: bytes) -> bytes:
    prefix = f"\x19Ethereum Signed Message:\n{len(msg)}".encode("utf-8")
    return keccak256(prefix + msg)

# --- EIP-712 minimal typed data (domain + MBEvent(bytes32 eventHash)) ---
def _abi_encode_uint256(x: int) -> bytes:
    return x.to_bytes(32, "big")

def _abi_encode_address(addr_hex: str) -> bytes:
    addr = bytes.fromhex(addr_hex[2:] if addr_hex.startswith("0x") else addr_hex)
    if len(addr) != 20:
        raise ValueError("address must be 20 bytes")
    return b"\x00" * 12 + addr

def _abi_encode_bytes32(b32: bytes) -> bytes:
    if len(b32) != 32:
        raise ValueError("bytes32 must be 32 bytes")
    return b32

def _abi_encode_string(s: str) -> bytes:
    # In EIP-712, dynamic types are encoded as keccak256(value) and treated as bytes32.
    return keccak256(s.encode("utf-8"))

def eip712_domain_separator(name: str, version: str, chain_id: int, verifying_contract: str) -> bytes:
    type_str = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    type_hash = keccak256(type_str.encode("utf-8"))
    encoded = (
        type_hash +
        _abi_encode_bytes32(_abi_encode_string(name)) +
        _abi_encode_bytes32(_abi_encode_string(version)) +
        _abi_encode_uint256(chain_id) +
        _abi_encode_address(verifying_contract)
    )
    return keccak256(encoded)

def eip712_struct_hash_mbevent(event_hash32: bytes) -> bytes:
    type_str = "MBEvent(bytes32 eventHash)"
    type_hash = keccak256(type_str.encode("utf-8"))
    return keccak256(type_hash + _abi_encode_bytes32(event_hash32))

def eip712_digest(domain_sep: bytes, struct_hash: bytes) -> bytes:
    return keccak256(b"\x19\x01" + domain_sep + struct_hash)

def sign_eip191_bytes32(msg_hash32: bytes, privkey: int) -> Tuple[int,int,int,bytes]:
    if len(msg_hash32) != 32:
        raise ValueError("msg_hash32 must be 32 bytes")
    digest = eip191_digest(msg_hash32)
    r,s,recid = ecdsa_sign(digest, privkey)
    return r,s,recid,digest

def sign_eip712_eventhash(event_hash32: bytes, privkey: int, *, name: str, version: str, chain_id: int, verifying_contract: str) -> Tuple[int,int,int,bytes,bytes,bytes]:
    if len(event_hash32) != 32:
        raise ValueError("event_hash32 must be 32 bytes")
    domain_sep = eip712_domain_separator(name, version, chain_id, verifying_contract)
    struct_hash = eip712_struct_hash_mbevent(event_hash32)
    digest = eip712_digest(domain_sep, struct_hash)
    r,s,recid = ecdsa_sign(digest, privkey)
    return r,s,recid,digest,domain_sep,struct_hash
