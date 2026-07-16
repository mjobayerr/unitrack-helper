/// Static configuration for the helper app.
///
/// [baseUrl] is compile-time so the service isolate can read it without any
/// plugin or storage round-trip. Override per build:
/// `flutter run --dart-define=UNITRACK_BASE_URL=http://192.168.0.10:8000`
class AppConfig {
  const AppConfig._();

  /// 10.0.2.2 is the Android emulator's alias for the host machine's loopback.
  static const String baseUrl = String.fromEnvironment(
    'UNITRACK_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// How often buffered fixes are POSTed. Spec §7.3: ~1-10 points per ~5s.
  static const int flushIntervalMs = 5000;

  /// Backend `GpsBatch.points` is capped at 50 (max_length=50); a longer batch
  /// is rejected with 422, so the buffer never grows past this.
  static const int maxBatchSize = 50;

  /// Metres of movement before the platform emits a new fix.
  static const int distanceFilterMeters = 5;

  static const Duration requestTimeout = Duration(seconds: 15);
}
