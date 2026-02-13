
# A2A over P2P Binding (LIBP2P+A2A) — Draft

This document defines a pragmatic binding to run A2A-style requests/responses over
P2P connections suitable for mobile devices (libp2p streams or WebRTC datachannels).

**Goal:** Keep A2A semantics (Agent Card, tasks, messages, artifacts) while letting peers
communicate without stable inbound HTTPS.

This is **binding guidance**, not a replacement for the core A2A spec.

---

## 1. Transport requirements

A conformant transport MUST provide:
- authenticated encryption on the connection (e.g., libp2p Noise, WebRTC DTLS)
- a bidirectional byte stream or message channel
- backpressure and max-message-size enforcement

---

## 2. Binding identifier (Agent Card)

Agents SHOULD declare a supported interface:

```json
{
  "url": "https://gateway.example/ipfs/<cid>/a2a-interface.json",
  "protocolBinding": "LIBP2P+A2A",
  "protocolVersion": "0.3.0"
}
```

`url` is a **locator** that can contain:
- libp2p multiaddrs
- WebRTC rendezvous parameters
- relay endpoints

The actual request/response traffic occurs over the P2P transport.

---

## 3. Wire format: JSON-RPC 2.0 framing

All A2A operations are encoded as JSON-RPC 2.0 messages.

### 3.1 Request
```json
{
  "jsonrpc": "2.0",
  "id": "uuid-or-int",
  "method": "a2a.message.send",
  "params": { ... }
}
```

### 3.2 Response
```json
{
  "jsonrpc": "2.0",
  "id": "same-as-request",
  "result": { ... }
}
```

### 3.3 Error
```json
{
  "jsonrpc": "2.0",
  "id": "same-as-request",
  "error": { "code": -32000, "message": "..." }
}
```

### 3.4 Notifications (streaming task updates)
For streaming task updates, the agent MAY send notifications:

```json
{
  "jsonrpc": "2.0",
  "method": "a2a.task.update",
  "params": { "taskId": "...", "status": { ... } }
}
```

---

## 4. Method mapping (recommended)

This repo recommends mapping A2A REST-style endpoints into JSON-RPC methods:

- `message/send` → `a2a.message.send`
- `tasks/get` → `a2a.tasks.get`
- `tasks/cancel` → `a2a.tasks.cancel`
- `tasks/subscribe` → `a2a.tasks.subscribe` (establishes notifications)

The exact `params` / `result` shapes SHOULD match the A2A JSON-RPC binding if/when used.
If you diverge, publish a compatibility note in your Agent Card (extensions section).

---

## 5. Correlation and ordering

- `id` MUST be unique per outstanding request on the same connection.
- Responses MAY arrive out of order.
- Streaming updates are asynchronous; clients MUST correlate by `taskId`.

---

## 6. Extension negotiation

If you rely on Antenna-specific A2A extensions:
- clients SHOULD request activation (per A2A extension activation mechanisms)
- agents SHOULD fail when required extensions are not supported

---

## 7. Practical notes for mobile

- Prefer a single persistent connection per peer while the app is foregrounded.
- Use relays for NAT traversal (libp2p relay v2 or TURN for WebRTC).
- For push-like behavior, combine store-and-forward relays with periodic polling.

