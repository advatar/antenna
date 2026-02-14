# antenna-relay

Deployable Rust relay server for MBP2P (Antenna).

Features:
- Store-and-forward envelope ingestion (`POST /` and `POST /v1/publish`)
- Topic event polling (`GET /v1/events?topic=...`)
- Gossip discovery (`GET /v1/discovery/relays`, `POST /v1/discovery/announce`)
- DHT-style rendezvous relay selection (`GET /v1/discovery/rendezvous?topic=...`)
- Multi-relay replication fanout with bounded hop propagation
- TTL pruning and payload-size limits

## Run

```bash
cargo run --manifest-path rust/antenna-relay/Cargo.toml -- \
  --bind 0.0.0.0:7878 \
  --public-url https://relay.example.com \
  --bootstrap https://relay-a.example.com,https://relay-b.example.com
```

## Environment Variables

- `ANTENNA_RELAY_BIND`
- `ANTENNA_RELAY_PUBLIC_URL`
- `ANTENNA_RELAY_BOOTSTRAP` (comma-separated)
- `ANTENNA_RELAY_MAX_PAYLOAD_BYTES`
- `ANTENNA_RELAY_TTL_SECS`
- `ANTENNA_RELAY_GOSSIP_INTERVAL_SECS`
- `ANTENNA_RELAY_GOSSIP_FANOUT`
- `ANTENNA_RELAY_REPLICATION_FANOUT`
- `ANTENNA_RELAY_MAX_REPLICATION_HOPS`
- `ANTENNA_RELAY_REQUEST_TIMEOUT_SECS`
