use thiserror::Error;

#[derive(Debug, Error)]
pub enum MBP2PError {
    #[error("invalid json: {0}")]
    InvalidJson(String),

    #[error("unsupported number (floats are not allowed): {0}")]
    UnsupportedNumber(String),

    #[error("canonicalization error: {0}")]
    Canonicalization(String),

    #[error("hex error: {0}")]
    Hex(String),

    #[error("crypto error: {0}")]
    Crypto(String),
}
