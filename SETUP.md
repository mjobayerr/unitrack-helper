# Helper app — GPS sender (partial slice) setup

This slice does one thing: stream **real device GPS** and POST batches to the
backend `POST /helper/gps` every ~5 s, authenticated with a hardcoded helper
token + bus_id. QR scan, SQLite buffer, SOS, foreground service = later slices.

Source is committed (`lib/`, `pubspec.yaml`). The Flutter **platform folders**
(`android/`, `ios/`) are NOT — generate them locally (step 2), since Flutter
wasn't available where this was scaffolded.

## 1. Backend: seed a bus + an approved helper, get a token
From `unitrack-backend/` (backend running, see its README):

```bash
# a) bus_id — copy the printed uuid
uv run python -m scripts.dev_seed_fleet          # prints bus_id=<uuid>

# b) register a helper, then approve it
curl -X POST localhost:8000/auth/register/helper \
  -H 'content-type: application/json' \
  -d '{"email":"bob@x.com","password":"pass1234","name":"Bob","phone":"017..."}'
HELPER_EMAIL=bob@x.com uv run python -m scripts.dev_seed_fleet   # approves bob

# c) login -> copy access_token
curl -X POST localhost:8000/auth/login \
  -H 'content-type: application/json' \
  -d '{"email":"bob@x.com","password":"pass1234"}'
```

## 2. Generate platform scaffolding + install deps
Needs Flutter SDK installed (`flutter --version`). From `unitrack-helper/`:

```bash
flutter create --platforms=android,ios --project-name unitrack_helper .
flutter pub get
```

`flutter create .` fills in `android/`/`ios/` and leaves existing `lib/` +
`pubspec.yaml` intact. If it warns it would overwrite `pubspec.yaml` or
`lib/main.dart`, keep the committed versions (they're in git).

## 3. Platform permissions (one-time, after step 2)
**Android** — `android/app/src/main/AndroidManifest.xml`, inside `<manifest>`:
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.INTERNET"/>
```
And on the `<application>` tag add `android:usesCleartextTraffic="true"` — dev
backend is plain `http://`, which Android blocks by default (POSTs silently fail otherwise).

**iOS** — `ios/Runner/Info.plist`:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Streams bus location while on a trip.</string>
<key>NSAppTransportSecurity</key>
<dict><key>NSAllowsArbitraryLoads</key><true/></dict>
```

## 4. Run
Pass the token + bus_id (or bake them into `lib/config.dart`):
```bash
flutter run \
  --dart-define=API_BASE=http://<LAN-IP-or-10.0.2.2>:8000 \
  --dart-define=HELPER_TOKEN=<access_token> \
  --dart-define=BUS_ID=<bus_uuid>
```
Tap **Start sending**, grant the location prompt. "Accepted" ticks up as the
backend 202s each batch.

## 5. Verify it reached Elasticsearch
```bash
curl "localhost:8000/track/nearby?lat=<your_lat>&lng=<your_lng>&radius_km=5"
```
Your bus should come back with a `distance_km`.
