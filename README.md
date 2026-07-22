# UniTrack Helper

Flutter app for the on-bus helper's phone — the only GPS sensor in the system
(no IoT hardware on the buses). This slice does one thing: a Start/Stop button
that streams the phone's location to the UniTrack backend.

## What it does

Start → a **location-typed foreground service** subscribes to the GPS stream,
buffers fixes, and `POST`s them to `/helper/gps` every 5 seconds. Stop → the
service and the notification go away.

Tracking keeps running with the screen off or the app minimised. That is the
entire point of the foreground service.

## Backend contract

| | |
|---|---|
| Endpoint | `POST /helper/gps` → `202 Accepted` |
| Auth | `Authorization: Bearer <access_token>` |
| Body | `{"bus_id": "<uuid>", "points": [{"lat","lng","ts","speed","heading","accuracy"}]}` |
| Caller must be | `role=helper` **and** `helpers.status='approved'` |

`test/gps_client_test.dart` pins this payload shape against the backend's
`GpsBatch` / `GpsPointIn` schemas.

## Running it

The backend must be up first (`docker compose up` in `unitrack-backend`).

```bash
flutter pub get
flutter run                     # emulator: talks to http://10.0.2.2:8000
```

`10.0.2.2` is the Android emulator's alias for the host machine's `localhost`.
On a physical phone that address is meaningless — point it at your machine's
LAN IP instead, and make sure uvicorn is bound to `0.0.0.0`:

```bash
flutter run --dart-define=UNITRACK_BASE_URL=http://192.168.0.10:8000
```

In the app: paste a **bus UUID** (from the `buses` table) and an **access
token** (from `POST /auth/login`), then press Start.

### Getting a bus ID and a token

From `unitrack-backend/`, with the stack up:

```bash
# 1. a bus — copy the printed uuid
BUS_REG_NO=DHK-01 uv run python -m scripts.dev_seed_fleet     # -> bus_id=<uuid>

# 2. register a helper
curl -X POST localhost:8000/auth/register/helper \
  -H 'content-type: application/json' \
  -d '{"email":"bob@x.com","password":"pass1234","name":"Bob","phone":"017..."}'

# 3. approve it (dev shortcut — there is no admin approval endpoint yet)
HELPER_EMAIL=bob@x.com uv run python -m scripts.dev_seed_fleet

# 4. log in — copy access_token
curl -X POST localhost:8000/auth/login \
  -H 'content-type: application/json' \
  -d '{"email":"bob@x.com","password":"pass1234"}'
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

Cleartext HTTP is permitted only for `10.0.2.2`, `localhost` and `127.0.0.1`
(see `res/xml/network_security_config.xml`). Everything else is HTTPS-only, in
debug and release alike. A deployed backend must be HTTPS.

## Known limits of this slice

- **The access token is pasted, and expires in 15 minutes.** There is no login
  screen and no refresh, so tracking dies mid-trip when the token expires. The
  app stops the service and says so rather than silently failing. Real fix: a
  login screen against `/auth/login` + refresh on 401.
- **No offline buffer.** Fixes are held in memory, capped at 50 (the backend's
  batch limit), oldest dropped first. Kill the app with no connectivity and
  those fixes are gone. The spec wants a SQLite/drift buffer here.
- **Bus ID is typed by hand** because no endpoint lists buses. A `GET
  /helper/buses` would let this be a dropdown.
- Battery optimisation exemption is not requested, so an aggressive OEM (Xiaomi,
  Oppo, Samsung) may still throttle the service.

## Layout

```
lib/
  main.dart                          app entry, opens the isolate status port
  src/
    config.dart                      base URL (--dart-define), batching knobs
    api/gps_client.dart              POST /helper/gps, typed auth vs retryable errors
    data/credential_store.dart       token -> secure storage, bus id -> prefs
    models/gps_fix.dart              mirrors GpsPointIn
    models/tracker_status.dart       service isolate -> UI status snapshot
    tracking/gps_task_handler.dart   runs in the service isolate: stream, buffer, POST
    tracking/tracking_controller.dart permissions + service lifecycle
    ui/home_page.dart                the form, the status card, the button
```

The task handler runs in **its own isolate** and shares no memory with the UI.
Credentials are handed to it over `sendDataToTask` and never persisted where the
service could read them back — an auto-restarted service without a token would
be a silent no-op, which is why auto-restart is off.
