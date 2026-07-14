# UniTrack — Helper

Flutter app (Android + iOS) for **UniTrack**, a university bus ticketing + live-tracking platform.

## Why this app matters

There is **no IoT hardware on the buses** — the **helper's phone is the only sensor**. This app streams GPS, scans student QR tickets, and reports seat occupancy. If it goes offline or dies mid-trip, the platform must degrade gracefully.

## What it does

- **Foreground GPS service** — buffers points to SQLite, POSTs batches every ~5 s.
- **Offline QR validation** — `mobile_scanner` reads the student's rotating QR; validates fully offline: HMAC check → time-slice window (±1 slice skew) → local SQLite nonce log for duplicate detection.
- **Ticket manifest** — periodically syncs a compact manifest (student ID, name, cached photo, rides-remaining, status) for dead-phone manual redemption and offline revocation.
- **Seat reports** — occupancy estimate vs capacity.
- **One-tap SOS** — offline priority-queued ahead of GPS, never rate-limited.

## Stack

Flutter (single codebase) · Android foreground service (uninterrupted GPS) · `mobile_scanner` (QR) · **SQLite via drift** (offline buffers) · background sync on reconnect.

## Contract

No backend code here. Talks only to the **[unitrack-backend](https://github.com/mjobayerr/unitrack-backend)** API. Dart models generated from its OpenAPI schema (`openapi-generator`).

## Sibling repos

- **[unitrack-backend](https://github.com/mjobayerr/unitrack-backend)** — FastAPI hub + workers (+ full spec).
- **[unitrack-web](https://github.com/mjobayerr/unitrack-web)** — Next.js student PWA + admin dashboard.

## Status

Pre-code (greenfield). Primary work lands in roadmap **P2** (GPS + trip lifecycle) and **P3** (offline validation + fraud sweep). Full spec lives in the backend repo.
