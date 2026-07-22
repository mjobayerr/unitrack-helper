# Background tracking — how it behaves, and what is verified

The whole point of this app is that the bus keeps reporting its position while
the helper's phone is in a pocket, the screen is off, or the app is not on
screen. This documents exactly how far that holds on each platform, and — just
as importantly — what has actually been tested versus only configured.

## Android — the primary platform

Tracking runs in a **location-typed foreground service** (`flutter_foreground_task`
+ `geolocator`). The service is a separate process from the UI, which is why it
survives things that close the UI.

| Event | What happens | Verified |
|---|---|---|
| App backgrounded (Home) | Keeps sending | ✅ on emulator |
| Screen locked | Keeps sending | ✅ on emulator |
| Swiped away from Recents | Service keeps running and sending; the ongoing notification stays | ✅ on emulator (task removed from Recents, process survived, GPS kept arriving) |
| OS kills the service (low memory) | `allowAutoRestart` brings it back; on restart it reads the bus id + refresh token from storage and resumes the still-live trip | ⚠️ configured, not yet reproduced |
| Access token expires mid-trip (15 min) | The service refreshes its own token via `ApiClient` and keeps going | ✅ unit-tested (`test/api_client_gps_test.dart`) |
| Reopen the app after a swipe | UI starts locked and asks for the PIN; after unlock the dashboard restores the live trip from `GET /helper/trips/active` | ⚠️ PIN-lock verified; trip-resume path exists but not yet driven end-to-end on device |

### The real-world catch: OEM battery managers

Stock Android (the emulator, Pixels) behaves as above. **Xiaomi, Realme, Oppo,
Vivo and Samsung do not.** Their battery managers kill background services
aggressively, and a swipe-away there will stop tracking unless the app is
exempted. This is most of the Bangladeshi phone market, so it matters here more
than almost anywhere.

Mitigations now in place:

- **Battery-optimisation exemption** — `ensurePermissions()` calls
  `requestIgnoreBatteryOptimization()` before the first trip. The helper sees a
  system dialog; granting it is what makes swipe-survival hold on these phones.
  Declining does not block tracking while the app is open.
- **`allowAutoRestart: true`** — if the service is killed anyway, it is
  restarted and resumes the live trip.

Neither can be verified on the stock emulator — they only matter on the OEM
phones that misbehave. **This must be tested on a real Xiaomi/Realme/Samsung
before it is trusted in production.** No amount of emulator testing substitutes.

## iOS — configured, not yet buildable here

The iOS project exists (`ios/`) and is configured for background location:

- `Info.plist`: `NSLocationWhenInUseUsageDescription`,
  `NSLocationAlwaysAndWhenInUseUsageDescription`, and `UIBackgroundModes`
  including `location`.
- `AppleSettings(allowBackgroundLocationUpdates: true,
  showBackgroundLocationIndicator: true, pauseLocationUpdatesAutomatically:
  false)` on the position stream (`gps_task_handler.dart`).

**None of this has been built or run.** Building iOS requires macOS + Xcode; it
cannot be done on Windows, where this was developed. Treat the iOS path as
"written, unverified" until it runs on a Mac and a real iPhone.

### iOS is fundamentally different, and one limit cannot be coded away

iOS has no foreground service. Background location works like this:

| Event | iOS behaviour |
|---|---|
| App backgrounded / screen locked | Keeps delivering location (blue status-bar pill), via the `location` background mode |
| **Force-quit** (swipe up in the app switcher) | **Location stops, and iOS will not relaunch the app for continuous updates.** |

That last row is an Apple platform decision, not a bug and not something the app
can override. Ride-hailing apps work around it by *also* registering for
Significant Location Change or region monitoring, which iOS **can** use to
relaunch a force-quit app in the background; the app then restarts precise
updates — with a coverage gap during the relaunch. That fallback is **not built
yet**. Until it is, the iOS rule for helpers is: leave the app running, do not
swipe it away. On Android, swiping away is fine.

## What to test before trusting this in the field

1. A real Xiaomi/Realme/Samsung: start a trip, swipe the app away, confirm the
   notification and GPS survive after granting the battery exemption.
2. A 20-minute-plus trip on a real phone, to confirm the token refresh keeps it
   alive past the 15-minute access-token lifetime.
3. iOS end-to-end on a Mac + iPhone: background delivery, and the force-quit
   behaviour above, so the limitation is confirmed and documented for helpers.
