
# Antenna PubSub Transport Notes

This file explains how to run the MBP2P layer over *any* pubsub-capable transport.

The protocol assumes **best-effort, at-least-once delivery** and tolerates duplicates.

---

## 1. Required topic naming
See `spec/MBP2P-SPEC.md` for canonical topic names.

---

## 2. Required payload wrapper
All pubsub messages MUST be `antenna.envelope.v1`.

---

## 3. Deduplication
Peers MUST deduplicate events by `event.id`.

---

## 4. Store-and-forward relays
To support mobile peers:
- relays SHOULD cache the last N days or last N MB per topic
- relays MAY answer sync queries (outside the pubsub layer) to help clients catch up

A simple sync RPC can be modeled as an A2A task (direct) or as a custom P2P RPC.

---

## 5. Payload size
Category manifests define `policy.maxEventSizeBytes`.
Peers MUST enforce local max sizes and SHOULD drop oversized payloads early.

