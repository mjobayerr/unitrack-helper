# UniTrack — Helper

Flutter app (Android + iOS) for **UniTrack**, a university bus ticketing + live-tracking platform.

## Why this app matters

There is **no IoT hardware on the buses** — the **helper's phone is the only sensor**. This app streams GPS, scans student QR tickets, and reports seat occupancy. If it goes offline or dies mid-trip, the platform must degrade gracefully.

## Status — GPS sender slice (partial)

The **only** thing built so far is the live-GPS sender: stream the device's real
GPS and POST batches to the backend every ~5 s. Everything else (QR scan, offline
buffer, seat reports, SOS, foreground service) is still to come — see [Roadmap](#roadmap).

Dart analyzes clean (`flutter analyze` → *No issues found*). It has **not** been
run on a device yet (needs a phone/emulator).

### What's built & how

| Piece | File | How it works |
|---|---|---|
| App shell + UI | [`lib/main.dart`](lib/main.dart) | One screen: shows backend, bus, live position, buffered count, accepted count, last HTTP status. A single **Start/Stop** button. |
| GPS capture | `lib/main.dart` (`geolocator`) | Requests location permission, then `getPositionStream` at high accuracy; every fix is pushed into an in-memory buffer. |
| Upload loop | `lib/main.dart` | A 5 s `Timer` flushes up to 50 buffered fixes as one JSON batch to `POST /helper/gps`. On failure the points are **put back** so the next tick retries (offline-first spirit — spec §7.3). |
| Config | [`lib/config.dart`](lib/config.dart) | Hardcoded `apiBase` / `helperToken` / `busId`, each overridable at run time with `--dart-define` (no rebuild, no secrets in git). |

The batch shape matches the backend `GpsBatch` schema: `{ bus_id, points: [{lat, lng, ts, speed, heading, accuracy}] }`. Auth is a **hardcoded helper JWT** for now (Bearer header) — a real login flow comes later.

## Stack

Flutter (single codebase) · `geolocator` (GPS stream + runtime permission) · `http` (POST). Later: Android **foreground service** (uninterrupted GPS), `mobile_scanner` (QR), **SQLite via drift** (offline buffer), background sync on reconnect.

## Run

The Flutter **platform folders** (`android/`, `ios/`) are not committed — generate
them locally. Full step-by-step (seed a bus, get a helper token, permissions,
run, verify in Elasticsearch) is in **[SETUP.md](SETUP.md)**. Short version:

```bash
flutter create --platforms=android,ios --project-name unitrack_helper .
flutter pub get
# add location + cleartext-http permissions (SETUP.md step 3), then:
flutter run \
  --dart-define=API_BASE=http://<LAN-IP-or-10.0.2.2>:8000 \
  --dart-define=HELPER_TOKEN=<access_token> \
  --dart-define=BUS_ID=<bus_uuid>
```

Two gotchas SETUP.md handles: Android blocks plain `http://` by default
(`usesCleartextTraffic`), and a real phone can't reach `localhost` (use the dev
box's LAN IP).

## Roadmap

- **Offline buffer** — persist fixes to SQLite (drift) so a dead network / app kill doesn't lose points (currently the buffer is in-memory only).
- **Trip lifecycle** — start/stop a trip; bind fixes to a `trip_id`.
- **Offline QR validation** — `mobile_scanner`; HMAC + time-slice + local nonce log (spec §7.5).
- **Seat reports**, **one-tap SOS** (offline-priority-queued), **login flow** (replace hardcoded token).
- Dart API models generated from the backend OpenAPI schema (`openapi-generator`).

## Contract

No backend code here. Talks only to the **[unitrack-backend](https://github.com/mjobayerr/unitrack-backend)** API (full spec lives there).

## Sibling repos

- **[unitrack-backend](https://github.com/mjobayerr/unitrack-backend)** — FastAPI hub + workers (+ full spec).
- **[unitrack-web](https://github.com/mjobayerr/unitrack-web)** — Next.js student PWA + admin dashboard.

---

_Parts of this project were built with the help of AI._
