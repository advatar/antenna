
# antenna-spec-tools-js (Reference)

This folder contains a small TypeScript reference implementation for the canonicalization
profile + eventId computation used in the Antenna distributed protocol.

It is intentionally dependency-light and avoids floats for deterministic interop.

## Build

```bash
cd js
npm install
npm run build
```

## Run interop (eventId vectors)

```bash
npm run test:interop
```
