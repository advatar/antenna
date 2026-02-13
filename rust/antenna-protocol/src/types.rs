use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MBEnvelope {
    #[serde(rename = "type")]
    pub r#type: String,
    pub topic: String,
    pub event: MBEvent,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MBAuthor {
    #[serde(rename = "type")]
    pub r#type: String, // "erc8004" | "ens" | "anon"
    pub agentRegistry: Option<String>,
    pub agentId: Option<i64>,
    pub ens: Option<String>,
    pub anonKey: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MBAuth {
    #[serde(rename = "type")]
    pub r#type: String,
    pub payload: serde_json::Map<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MBPart {
    pub kind: String, // "text" | "file" | "data"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bytesBase64: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mediaType: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MBEvent {
    #[serde(rename = "type")]
    pub r#type: String,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,

    pub kind: String,
    pub category: String,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub thread: Option<String>,

    pub parents: Vec<String>,
    pub author: MBAuthor,
    pub createdAt: String,
    pub parts: Vec<MBPart>,
    pub extensions: Vec<String>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub metadata: Option<Value>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub auth: Option<MBAuth>,
}
