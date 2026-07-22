# UniTrack Helper

Flutter app for the on-bus helper's phone — **the only GPS sensor in the system**
(no IoT hardware on the buses). The helper signs in, starts a trip, and the phone
streams its location to the UniTrack backend for the whole trip while also
handling passenger counts and emergency alerts.

Talks only to **[unitrack-backend](https://github.com/mjobayerr/unitrack-backend)**.

## Status at a glance

**Functional** — runs on the Android emulator against the real backend, end to
end (sign in → start trip → live GPS reaches Elasticsearch → seats → SOS → end):

| Feature | State |
|---|---|
| Register (new helper → `pending_approval`) | ✅ |
| Login (email + password) then 4-digit **PIN** unlock | ✅ |
| Dashboard: trip status, live tracking indicator | ✅ |
| Start / end trip with bus + route pickers (`/fleet/*`) | ✅ |
| Background GPS via location foreground service, batched every 5 s | ✅ |
| **Token refresh inside the service** — no more dying at 15 min | ✅ (unit-tested) |
| **Durable SQLite outbox** — fixes survive a crash / offline gap | ✅ |
| Survives swipe-away on stock Android; auto-restart + battery-exemption for OEM phones | ✅ config / ⚠️ needs a real Xiaomi/Realme to confirm |
| Passenger counter (seat reports) | ✅ |
| Emergency / SOS screen | ✅ |
| Profile + sign out | ✅ |

**Not built yet:**

| Feature | Notes |
|---|---|
| QR ticket scanning | Needs the backend ticket/wallet subsystem (bKash-gated) |
| iOS | Scaffolded + configured, **not built** — needs a Mac; and iOS force-quit stops tracking (Apple limit). See [`docs/background-tracking.md`](docs/background-tracking.md) |
| Significant-location relaunch (iOS force-quit recovery) | Future |
| Admin approval UI | Lives in the (unbuilt) web app; approve via the backend for now |

## Backend contract

Full login-based auth; every call carries a Bearer access token that the app
refreshes on a 401. Caller for trip/GPS actions must be `role=helper` **and**
`helpers.status='approved'`. GPS payload (`POST /helper/gps` → `202`) is pinned
against the backend's `GpsBatch` / `GpsPointIn` schemas by
[`test/api_client_gps_test.dart`](test/api_client_gps_test.dart).

## Running it

The backend must be up first (`docker compose up` in `unitrack-backend`).

### On the Android emulator

```bash
flutter pub get
flutter run                     # talks to http://10.0.2.2:8000
```

`10.0.2.2` is the emulator's alias for the host machine's `localhost`.

### On a real Android phone

`10.0.2.2` means nothing on a physical device, so point the app at your
machine's LAN IP and bind uvicorn to `0.0.0.0`:

```bash
flutter run --dart-define=UNITRACK_BASE_URL=http://192.168.0.10:8000
```

Cleartext `http://` to a LAN IP is blocked by default; the **debug** build
carries a network-security override that permits it
(`android/app/src/debug/res/xml/network_security_config.xml`), so this works out
of the box for testing. **Release builds stay HTTPS-only** — a deployed backend
must be `https://`, and then no override is involved:

```bash
flutter build apk --release --dart-define=UNITRACK_BASE_URL=https://api.yourschool.edu
```

### Signing in

The app is login-based — no more pasting tokens. A helper:

1. **Registers** in the app (Create an account), which makes a `pending_approval`
   account. They cannot sign in yet.
2. Is **approved by an admin** — `POST /admin/helpers/{id}/approve` (see the
   backend's `docs/auth.md`). For dev you can shortcut this with
   `HELPER_EMAIL=bob@x.com python -m scripts.dev_seed_fleet`.
3. **Signs in** once with email + password, sets a 4-digit **PIN**, and from then
   on only needs the PIN.

Buses and routes come from `GET /fleet/*` and are picked from dropdowns when
starting a trip — nothing is typed by hand.

Seed a bus and routes first, from `unitrack-backend/`:

```bash
BUS_REG_NO=DHK-01 python -m scripts.dev_seed_fleet   # a bus
python -m scripts.dev_seed_routes                    # stops + routes
```

Then confirm the fixes landed in Elasticsearch (the backend worker must be
running):

```bash
curl "localhost:8000/track/nearby?lat=<your_lat>&lng=<your_lng>&radius_km=5"
```

Your bus comes back with a `distance_km`.

## Permissions

| Permission | Why |
|---|---|
| `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` | the GPS fixes |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_LOCATION` | keep sending when backgrounded |
| `POST_NOTIFICATIONS` | Android 13+ gates the service's ongoing notification |
| `WAKE_LOCK` | keep the CPU up between fixes |
| `INTERNET` | reach the backend |

`ACCESS_BACKGROUND_LOCATION` is **not** requested, and should not be added. The
location-typed foreground service already grants background access while it
runs; the extra permission would buy nothing and invites Play Store review.

**Release builds are HTTPS-only** — a deployed backend must be `https://`. For
LAN testing on a real phone, **debug** builds carry a cleartext override
(`android/app/src/debug/res/xml/network_security_config.xml`); it never applies
to release. See "On a real Android phone" above.

## Known limitations

- **Swipe-away on OEM phones.** Verified surviving on stock Android. Xiaomi /
  Realme / Oppo / Samsung battery managers still kill background services unless
  the helper grants the battery-optimisation exemption the app requests. Not
  reproducible on the stock emulator — needs a real device.
- **iOS is unverified** (needs a Mac to build) and stops tracking on force-quit
  (Apple limit). See [`docs/background-tracking.md`](docs/background-tracking.md).
- **QR ticket scanning is absent** — waits on the backend ticket/wallet
  subsystem, which is bKash-gated.
- The `flutter_foreground_task` plugin triggers a Kotlin-Gradle-Plugin
  deprecation warning; builds fine today, worth watching for a future Flutter.

## Layout

```
lib/
  main.dart                          app entry; builds ApiClient + controllers, opens the isolate status port
  src/
    app.dart                         MaterialApp + go_router, session-driven redirects
    theme/app_theme.dart             Material 3 seed theme (light/dark), responsive helpers
    config.dart                      base URL (--dart-define), batching knobs
    api/api_client.dart              all endpoints; 401 → refresh → retry (single-flight)
    data/
      session_store.dart             refresh token + PBKDF2 PIN verifier in secure storage
      credential_store.dart          bus id + access token the service isolate reads
      gps_queue.dart                 durable SQLite outbox (peek / ackThrough)
    models/api_models.dart           DTOs mirroring the backend schemas
    models/gps_fix.dart              mirrors GpsPointIn
    state/
      session_controller.dart        auth journey: signedOut → needsPin → locked → ready
      trip_controller.dart           the live trip, seats, alerts, fleet pickers
      app_scope.dart                 InheritedWidget wiring for the two controllers
    tracking/
      gps_task_handler.dart          service isolate: stream → SQLite → POST, refreshes its own token
      tracking_controller.dart       permissions, battery exemption, service lifecycle
    ui/                              login · register · pin · dashboard · start_trip · counter · emergency · profile
```

The task handler runs in **its own isolate** and shares no memory with the UI.
It reads the session from secure storage and **refreshes its own token**, so a
restarted service resumes the live trip on its own — which is why auto-restart
is now safe and enabled.
