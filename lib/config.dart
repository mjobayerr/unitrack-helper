/// Hardcoded config for the partial GPS-sender slice.
///
/// Edit the defaults below, OR override at run time without touching the file:
///   flutter run \
///     --dart-define=API_BASE=http://192.168.1.50:8000 \
///     --dart-define=HELPER_TOKEN=eyJ... \
///     --dart-define=BUS_ID=<buses.id uuid>
class Config {
  /// Backend base URL.
  /// - Android emulator: 10.0.2.2 is the host's localhost (default below).
  /// - Real phone: use your dev box's LAN IP (e.g. http://192.168.x.x:8000).
  ///   The phone cannot reach "localhost" — that's the phone itself.
  static const apiBase =
      String.fromEnvironment('API_BASE', defaultValue: 'http://10.0.2.2:8000');

  /// Helper access token — a JWT from POST /auth/login for an APPROVED helper.
  /// Access tokens expire in 15 min (ACCESS_TOKEN_TTL_MIN); re-mint for a long test.
  static const helperToken =
      String.fromEnvironment('HELPER_TOKEN', defaultValue: 'PASTE_HELPER_ACCESS_TOKEN');

  /// The bus this device is bound to — a buses.id UUID from the backend
  /// (print it with `scripts.dev_seed_fleet`).
  static const busId =
      String.fromEnvironment('BUS_ID', defaultValue: 'PASTE_BUS_UUID');

  /// Batch flush cadence — spec §7.3 is ~5 s.
  static const flushInterval = Duration(seconds: 5);
}
