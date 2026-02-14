use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use antenna_protocol::types::MBEnvelope;
use anyhow::{anyhow, Context, Result};
use axum::extract::{Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::IntoResponse;
use axum::routing::{get, post};
use axum::{Json, Router};
use bytes::Bytes;
use clap::Parser;
use reqwest::Url;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

const ENVELOPE_TYPE: &str = "antenna.envelope.v1";
const EVENT_TYPE: &str = "antenna.event.v1";
const DEFAULT_MAX_PAYLOAD_BYTES: usize = 64 * 1024;
const DEFAULT_TTL_SECS: u64 = 60 * 60 * 24;
const DEFAULT_GOSSIP_INTERVAL_SECS: u64 = 30;
const DEFAULT_GOSSIP_FANOUT: usize = 8;
const DEFAULT_REPLICATION_FANOUT: usize = 3;
const DEFAULT_MAX_REPLICATION_HOPS: u8 = 2;
const DEFAULT_REQUEST_TIMEOUT_SECS: u64 = 4;

#[derive(Debug, Clone, Parser)]
#[command(
    name = "antenna-relay",
    about = "Antenna (MBP2P) decentralized store-and-forward relay with gossip discovery"
)]
struct Cli {
    #[arg(long, env = "ANTENNA_RELAY_BIND", default_value = "127.0.0.1:7878")]
    bind: String,
    #[arg(long, env = "ANTENNA_RELAY_PUBLIC_URL")]
    public_url: Option<String>,
    #[arg(long, env = "ANTENNA_RELAY_BOOTSTRAP", value_delimiter = ',')]
    bootstrap: Vec<String>,
    #[arg(
        long,
        env = "ANTENNA_RELAY_MAX_PAYLOAD_BYTES",
        default_value_t = DEFAULT_MAX_PAYLOAD_BYTES
    )]
    max_payload_bytes: usize,
    #[arg(long, env = "ANTENNA_RELAY_TTL_SECS", default_value_t = DEFAULT_TTL_SECS)]
    ttl_secs: u64,
    #[arg(
        long,
        env = "ANTENNA_RELAY_GOSSIP_INTERVAL_SECS",
        default_value_t = DEFAULT_GOSSIP_INTERVAL_SECS
    )]
    gossip_interval_secs: u64,
    #[arg(
        long,
        env = "ANTENNA_RELAY_GOSSIP_FANOUT",
        default_value_t = DEFAULT_GOSSIP_FANOUT
    )]
    gossip_fanout: usize,
    #[arg(
        long,
        env = "ANTENNA_RELAY_REPLICATION_FANOUT",
        default_value_t = DEFAULT_REPLICATION_FANOUT
    )]
    replication_fanout: usize,
    #[arg(
        long,
        env = "ANTENNA_RELAY_MAX_REPLICATION_HOPS",
        default_value_t = DEFAULT_MAX_REPLICATION_HOPS
    )]
    max_replication_hops: u8,
    #[arg(
        long,
        env = "ANTENNA_RELAY_REQUEST_TIMEOUT_SECS",
        default_value_t = DEFAULT_REQUEST_TIMEOUT_SECS
    )]
    request_timeout_secs: u64,
}

#[derive(Debug, Clone)]
struct RelayConfig {
    bind: String,
    public_url: String,
    max_payload_bytes: usize,
    ttl_secs: u64,
    gossip_interval_secs: u64,
    gossip_fanout: usize,
    replication_fanout: usize,
    max_replication_hops: u8,
    request_timeout_secs: u64,
}

type SharedState = Arc<RwLock<RelayState>>;

#[derive(Debug, Clone)]
struct RelayState {
    config: RelayConfig,
    known_relays: HashMap<String, KnownRelay>,
    topics: HashMap<String, Vec<StoredEnvelope>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct KnownRelay {
    url: String,
    source: String,
    last_seen_ms: i64,
    failures: u32,
}

#[derive(Debug, Clone, Serialize)]
struct StoredEnvelope {
    received_at_ms: i64,
    envelope: MBEnvelope,
}

#[derive(Debug, Serialize)]
struct ErrorResponse {
    ok: bool,
    error: String,
}

#[derive(Debug, Serialize)]
struct PublishResponse {
    ok: bool,
    received_at_ms: i64,
    relay_url: String,
    replicated: usize,
}

#[derive(Debug, Deserialize)]
struct EventsQuery {
    topic: String,
    since_ms: Option<i64>,
    limit: Option<usize>,
}

#[derive(Debug, Serialize)]
struct EventsResponse {
    ok: bool,
    topic: String,
    events: Vec<StoredEnvelope>,
}

#[derive(Debug, Serialize, Deserialize)]
struct DiscoveryRelaysResponse {
    ok: bool,
    relays: Vec<String>,
    generated_at_ms: i64,
}

#[derive(Debug, Deserialize, Serialize)]
struct DiscoveryAnnounceRequest {
    relay_url: String,
    known_relays: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct RendezvousQuery {
    topic: String,
    limit: Option<usize>,
}

#[derive(Debug, Serialize)]
struct RendezvousResponse {
    ok: bool,
    topic: String,
    relays: Vec<String>,
}

#[tokio::main]
async fn main() -> Result<()> {
    init_tracing();
    let cli = Cli::parse();
    let config = build_config(&cli)?;

    let mut state = RelayState {
        config: config.clone(),
        known_relays: HashMap::new(),
        topics: HashMap::new(),
    };
    state.merge_relay(&config.public_url, "self");
    for bootstrap in &cli.bootstrap {
        if let Some(url) = normalize_relay_url(bootstrap) {
            state.merge_relay(&url, "bootstrap");
        }
    }
    let shared = Arc::new(RwLock::new(state));

    spawn_prune_loop(shared.clone());
    spawn_gossip_loop(shared.clone());

    let app = Router::new()
        .route("/", post(publish_envelope_compat))
        .route("/v1/publish", post(publish_envelope))
        .route("/v1/events", get(get_topic_events))
        .route("/v1/discovery/relays", get(get_discovery_relays))
        .route("/v1/discovery/announce", post(post_discovery_announce))
        .route("/v1/discovery/rendezvous", get(get_discovery_rendezvous))
        .route("/v1/health", get(get_health))
        .with_state(shared.clone());

    let listener = tokio::net::TcpListener::bind(&config.bind)
        .await
        .with_context(|| format!("bind {}", config.bind))?;
    info!(
        bind = %config.bind,
        public_url = %config.public_url,
        "antenna relay started"
    );
    axum::serve(listener, app)
        .await
        .context("serve antenna relay")?;
    Ok(())
}

fn init_tracing() {
    let filter =
        std::env::var("RUST_LOG").unwrap_or_else(|_| "info,antenna_relay=debug".to_string());
    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_target(false)
        .compact()
        .init();
}

fn build_config(cli: &Cli) -> Result<RelayConfig> {
    let public_raw = cli
        .public_url
        .clone()
        .unwrap_or_else(|| format!("http://{}", cli.bind));
    let public_url = normalize_relay_url(&public_raw)
        .ok_or_else(|| anyhow!("invalid --public-url: {public_raw}"))?;
    Ok(RelayConfig {
        bind: cli.bind.clone(),
        public_url,
        max_payload_bytes: cli.max_payload_bytes.max(1024),
        ttl_secs: cli.ttl_secs.max(60),
        gossip_interval_secs: cli.gossip_interval_secs.max(5),
        gossip_fanout: cli.gossip_fanout.max(1),
        replication_fanout: cli.replication_fanout.max(1),
        max_replication_hops: cli.max_replication_hops.max(1),
        request_timeout_secs: cli.request_timeout_secs.max(1),
    })
}

async fn get_health(State(state): State<SharedState>) -> impl IntoResponse {
    let guard = state.read().await;
    let topics = guard.topics.len();
    let relays = guard.known_relays.len();
    let body = serde_json::json!({
        "ok": true,
        "service": "antenna-relay",
        "topics": topics,
        "knownRelays": relays,
        "publicUrl": guard.config.public_url,
        "tsMs": now_ms(),
    });
    (StatusCode::OK, Json(body))
}

async fn publish_envelope_compat(
    State(state): State<SharedState>,
    headers: HeaderMap,
    body: Bytes,
) -> impl IntoResponse {
    publish_inner(state, headers, body).await
}

async fn publish_envelope(
    State(state): State<SharedState>,
    headers: HeaderMap,
    body: Bytes,
) -> impl IntoResponse {
    publish_inner(state, headers, body).await
}

async fn publish_inner(
    state: SharedState,
    headers: HeaderMap,
    body: Bytes,
) -> (StatusCode, Json<serde_json::Value>) {
    let config = {
        let guard = state.read().await;
        guard.config.clone()
    };
    if body.is_empty() {
        return bad_request("empty payload");
    }
    if body.len() > config.max_payload_bytes {
        return (
            StatusCode::PAYLOAD_TOO_LARGE,
            Json(serde_json::json!(ErrorResponse {
                ok: false,
                error: format!(
                    "payload too large ({} > {})",
                    body.len(),
                    config.max_payload_bytes
                ),
            })),
        );
    }

    let envelope = match serde_json::from_slice::<MBEnvelope>(&body) {
        Ok(value) => value,
        Err(err) => return bad_request(&format!("invalid envelope json: {err}")),
    };
    if let Err(err) = validate_envelope(&envelope) {
        return bad_request(&err);
    }

    let received_at_ms = {
        let mut guard = state.write().await;
        guard.store_envelope(envelope.clone())
    };
    let hop = parse_hop(&headers);
    let replicated = if hop < config.max_replication_hops {
        replicate_to_peers(state.clone(), &envelope, &body, hop + 1).await
    } else {
        0
    };
    (
        StatusCode::OK,
        Json(serde_json::json!(PublishResponse {
            ok: true,
            received_at_ms,
            relay_url: config.public_url,
            replicated,
        })),
    )
}

async fn get_topic_events(
    State(state): State<SharedState>,
    Query(query): Query<EventsQuery>,
) -> impl IntoResponse {
    let topic = query.topic.trim().to_string();
    if topic.is_empty() {
        return bad_request("topic query parameter is required");
    }
    let since_ms = query.since_ms.unwrap_or(0);
    let limit = query.limit.unwrap_or(50).clamp(1, 500);
    let events = {
        let guard = state.read().await;
        guard.events_for_topic(&topic, since_ms, limit)
    };
    (
        StatusCode::OK,
        Json(serde_json::json!(EventsResponse {
            ok: true,
            topic,
            events,
        })),
    )
}

async fn get_discovery_relays(State(state): State<SharedState>) -> impl IntoResponse {
    let relays = {
        let guard = state.read().await;
        guard.sorted_relays()
    };
    (
        StatusCode::OK,
        Json(serde_json::json!(DiscoveryRelaysResponse {
            ok: true,
            relays,
            generated_at_ms: now_ms(),
        })),
    )
}

async fn post_discovery_announce(
    State(state): State<SharedState>,
    Json(payload): Json<DiscoveryAnnounceRequest>,
) -> impl IntoResponse {
    let mut merged = 0usize;
    {
        let mut guard = state.write().await;
        if guard.merge_relay(&payload.relay_url, "announce") {
            merged += 1;
        }
        for relay in &payload.known_relays {
            if guard.merge_relay(relay, "announce") {
                merged += 1;
            }
        }
    }
    debug!(merged, "processed discovery announce");
    get_discovery_relays(State(state)).await
}

async fn get_discovery_rendezvous(
    State(state): State<SharedState>,
    Query(query): Query<RendezvousQuery>,
) -> impl IntoResponse {
    if query.topic.trim().is_empty() {
        return bad_request("topic query parameter is required");
    }
    let limit = query.limit.unwrap_or(8).clamp(1, 64);
    let relays = {
        let guard = state.read().await;
        guard.rendezvous_relays(&query.topic, limit)
    };
    (
        StatusCode::OK,
        Json(serde_json::json!(RendezvousResponse {
            ok: true,
            topic: query.topic,
            relays,
        })),
    )
}

fn bad_request(message: &str) -> (StatusCode, Json<serde_json::Value>) {
    (
        StatusCode::BAD_REQUEST,
        Json(serde_json::json!(ErrorResponse {
            ok: false,
            error: message.to_string(),
        })),
    )
}

fn validate_envelope(envelope: &MBEnvelope) -> std::result::Result<(), String> {
    if envelope.r#type != ENVELOPE_TYPE {
        return Err(format!(
            "unexpected envelope type: {} (expected {ENVELOPE_TYPE})",
            envelope.r#type
        ));
    }
    if envelope.event.r#type != EVENT_TYPE {
        return Err(format!(
            "unexpected event type: {} (expected {EVENT_TYPE})",
            envelope.event.r#type
        ));
    }
    if envelope.topic.trim().is_empty() {
        return Err("topic is empty".to_string());
    }
    if envelope.event.category.trim().is_empty() {
        return Err("event.category is empty".to_string());
    }
    Ok(())
}

fn parse_hop(headers: &HeaderMap) -> u8 {
    headers
        .get("x-antenna-relay-hop")
        .and_then(|value| value.to_str().ok())
        .and_then(|s| s.parse::<u8>().ok())
        .unwrap_or(0)
}

fn spawn_prune_loop(state: SharedState) {
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_secs(10)).await;
            let mut guard = state.write().await;
            let removed = guard.prune_expired();
            if removed > 0 {
                debug!(removed, "pruned expired envelopes");
            }
        }
    });
}

fn spawn_gossip_loop(state: SharedState) {
    tokio::spawn(async move {
        loop {
            let (interval_secs, peers) = {
                let guard = state.read().await;
                (
                    guard.config.gossip_interval_secs,
                    guard.known_peer_candidates(guard.config.gossip_fanout),
                )
            };
            for peer in peers {
                if let Err(err) = gossip_with_peer(state.clone(), &peer).await {
                    warn!(peer = %peer, error = %err, "relay gossip failed");
                    let mut guard = state.write().await;
                    guard.mark_failure(&peer);
                }
            }
            tokio::time::sleep(Duration::from_secs(interval_secs)).await;
        }
    });
}

async fn gossip_with_peer(state: SharedState, peer: &str) -> Result<()> {
    let (request_timeout_secs, self_url, known_relays) = {
        let guard = state.read().await;
        (
            guard.config.request_timeout_secs,
            guard.config.public_url.clone(),
            guard.sorted_relays(),
        )
    };
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(request_timeout_secs))
        .build()
        .context("build reqwest client")?;

    let relays_endpoint = format!("{peer}/v1/discovery/relays");
    let discovered = client
        .get(&relays_endpoint)
        .send()
        .await
        .with_context(|| format!("GET {relays_endpoint}"))?
        .error_for_status()
        .with_context(|| format!("status from {relays_endpoint}"))?
        .json::<DiscoveryRelaysResponse>()
        .await
        .with_context(|| format!("decode discovery response from {relays_endpoint}"))?;

    let announce_endpoint = format!("{peer}/v1/discovery/announce");
    let announce_body = DiscoveryAnnounceRequest {
        relay_url: self_url.clone(),
        known_relays,
    };
    let _ = client
        .post(&announce_endpoint)
        .json(&announce_body)
        .send()
        .await
        .with_context(|| format!("POST {announce_endpoint}"))?
        .error_for_status()
        .with_context(|| format!("status from {announce_endpoint}"))?;

    let mut guard = state.write().await;
    guard.mark_seen(peer);
    guard.merge_relay(&self_url, "self");
    for relay in discovered.relays {
        guard.merge_relay(&relay, "gossip");
    }
    Ok(())
}

async fn replicate_to_peers(
    state: SharedState,
    envelope: &MBEnvelope,
    body: &Bytes,
    hop: u8,
) -> usize {
    let (request_timeout_secs, fanout, peers) = {
        let guard = state.read().await;
        (
            guard.config.request_timeout_secs,
            guard.config.replication_fanout,
            guard.rendezvous_relays(&envelope.topic, guard.config.replication_fanout + 1),
        )
    };
    let targets: Vec<String> = peers.into_iter().take(fanout).collect();
    if targets.is_empty() {
        return 0;
    }
    let client = match reqwest::Client::builder()
        .timeout(Duration::from_secs(request_timeout_secs))
        .build()
    {
        Ok(value) => value,
        Err(err) => {
            warn!(error = %err, "failed to build replicate client");
            return 0;
        }
    };

    let mut replicated = 0usize;
    for relay in targets {
        let endpoint = format!("{relay}/v1/publish");
        let result = client
            .post(&endpoint)
            .header("x-antenna-relay-hop", hop.to_string())
            .body(body.clone())
            .header("content-type", "application/json")
            .send()
            .await;
        match result {
            Ok(response) if response.status().is_success() => {
                replicated += 1;
                let mut guard = state.write().await;
                guard.mark_seen(&relay);
            }
            Ok(response) => {
                warn!(relay = %relay, status = %response.status(), "replicate publish failed");
                let mut guard = state.write().await;
                guard.mark_failure(&relay);
            }
            Err(err) => {
                warn!(relay = %relay, error = %err, "replicate publish error");
                let mut guard = state.write().await;
                guard.mark_failure(&relay);
            }
        }
    }
    replicated
}

impl RelayState {
    fn merge_relay(&mut self, raw: &str, source: &str) -> bool {
        let Some(url) = normalize_relay_url(raw) else {
            return false;
        };
        let now = now_ms();
        match self.known_relays.get_mut(&url) {
            Some(existing) => {
                existing.last_seen_ms = now;
                true
            }
            None => {
                self.known_relays.insert(
                    url.clone(),
                    KnownRelay {
                        url,
                        source: source.to_string(),
                        last_seen_ms: now,
                        failures: 0,
                    },
                );
                true
            }
        }
    }

    fn mark_seen(&mut self, relay: &str) {
        if let Some(url) = normalize_relay_url(relay) {
            let entry = self.known_relays.entry(url.clone()).or_insert(KnownRelay {
                url,
                source: "seen".to_string(),
                last_seen_ms: now_ms(),
                failures: 0,
            });
            entry.last_seen_ms = now_ms();
            entry.failures = 0;
        }
    }

    fn mark_failure(&mut self, relay: &str) {
        if let Some(url) = normalize_relay_url(relay) {
            let entry = self.known_relays.entry(url.clone()).or_insert(KnownRelay {
                url,
                source: "seen".to_string(),
                last_seen_ms: now_ms(),
                failures: 0,
            });
            entry.failures = entry.failures.saturating_add(1);
        }
    }

    fn sorted_relays(&self) -> Vec<String> {
        let mut relays: Vec<String> = self.known_relays.keys().cloned().collect();
        relays.sort();
        relays
    }

    fn known_peer_candidates(&self, limit: usize) -> Vec<String> {
        let mut candidates: Vec<_> = self
            .known_relays
            .values()
            .filter(|relay| relay.url != self.config.public_url)
            .cloned()
            .collect();
        candidates.sort_by_key(|relay| (relay.failures, -relay.last_seen_ms));
        candidates
            .into_iter()
            .take(limit)
            .map(|relay| relay.url)
            .collect()
    }

    fn rendezvous_relays(&self, topic: &str, limit: usize) -> Vec<String> {
        let topic_hash = sha256(topic.as_bytes());
        let mut relays: Vec<String> = self
            .known_relays
            .keys()
            .filter(|relay| relay.as_str() != self.config.public_url)
            .cloned()
            .collect();
        relays.sort_by(|left, right| {
            let lhs = xor_distance(&topic_hash, &sha256(left.as_bytes()));
            let rhs = xor_distance(&topic_hash, &sha256(right.as_bytes()));
            lhs.cmp(&rhs)
        });
        relays.into_iter().take(limit).collect()
    }

    fn store_envelope(&mut self, envelope: MBEnvelope) -> i64 {
        let received_at_ms = now_ms();
        self.topics
            .entry(envelope.topic.clone())
            .or_default()
            .push(StoredEnvelope {
                received_at_ms,
                envelope,
            });
        received_at_ms
    }

    fn events_for_topic(&self, topic: &str, since_ms: i64, limit: usize) -> Vec<StoredEnvelope> {
        let mut result = self
            .topics
            .get(topic)
            .map(|events| {
                events
                    .iter()
                    .filter(|entry| entry.received_at_ms > since_ms)
                    .cloned()
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        if result.len() > limit {
            let keep_from = result.len() - limit;
            result = result.split_off(keep_from);
        }
        result
    }

    fn prune_expired(&mut self) -> usize {
        let cutoff = now_ms() - (self.config.ttl_secs as i64 * 1000);
        let mut removed = 0usize;
        let mut empty_topics = Vec::new();
        for (topic, events) in &mut self.topics {
            let before = events.len();
            events.retain(|entry| entry.received_at_ms >= cutoff);
            removed += before.saturating_sub(events.len());
            if events.is_empty() {
                empty_topics.push(topic.clone());
            }
        }
        for topic in empty_topics {
            self.topics.remove(&topic);
        }
        removed
    }
}

fn sha256(bytes: &[u8]) -> [u8; 32] {
    let digest = Sha256::digest(bytes);
    let mut out = [0u8; 32];
    out.copy_from_slice(&digest);
    out
}

fn xor_distance(left: &[u8; 32], right: &[u8; 32]) -> [u8; 32] {
    let mut out = [0u8; 32];
    for (idx, byte) in out.iter_mut().enumerate() {
        *byte = left[idx] ^ right[idx];
    }
    out
}

fn normalize_relay_url(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }
    let prefixed = if trimmed.contains("://") {
        trimmed.to_string()
    } else {
        format!("http://{trimmed}")
    };
    let mut url = Url::parse(&prefixed).ok()?;
    if url.scheme() != "http" && url.scheme() != "https" {
        return None;
    }
    url.set_query(None);
    url.set_fragment(None);
    let path = url.path().trim_end_matches('/').to_string();
    if path.is_empty() {
        url.set_path("");
    } else {
        url.set_path(&path);
    }
    let mut normalized = url.to_string();
    while normalized.ends_with('/') {
        normalized.pop();
    }
    Some(normalized)
}

fn now_ms() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_millis() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_relay_url_strips_query_and_trailing_slash() {
        let actual = normalize_relay_url("https://relay.example.com:8080/path/?a=1#x");
        assert_eq!(
            actual.as_deref(),
            Some("https://relay.example.com:8080/path")
        );
    }

    #[test]
    fn rendezvous_sorting_is_stable() {
        let config = RelayConfig {
            bind: "127.0.0.1:7878".to_string(),
            public_url: "http://self".to_string(),
            max_payload_bytes: DEFAULT_MAX_PAYLOAD_BYTES,
            ttl_secs: DEFAULT_TTL_SECS,
            gossip_interval_secs: DEFAULT_GOSSIP_INTERVAL_SECS,
            gossip_fanout: DEFAULT_GOSSIP_FANOUT,
            replication_fanout: DEFAULT_REPLICATION_FANOUT,
            max_replication_hops: DEFAULT_MAX_REPLICATION_HOPS,
            request_timeout_secs: DEFAULT_REQUEST_TIMEOUT_SECS,
        };
        let mut state = RelayState {
            config,
            known_relays: HashMap::new(),
            topics: HashMap::new(),
        };
        state.merge_relay("http://self", "self");
        state.merge_relay("http://relay-1", "test");
        state.merge_relay("http://relay-2", "test");
        state.merge_relay("http://relay-3", "test");

        let first = state.rendezvous_relays("mb/v1/help/ai.antenna.eth", 3);
        let second = state.rendezvous_relays("mb/v1/help/ai.antenna.eth", 3);
        assert_eq!(first, second);
        assert_eq!(first.len(), 3);
    }
}
