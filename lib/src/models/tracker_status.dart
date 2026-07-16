/// A snapshot of the tracker, sent from the service isolate to the UI isolate.
///
/// Only primitives, String, Map and List survive the isolate hop, so this is
/// carried as a JSON string.
class TrackerStatus {
  const TrackerStatus({
    this.sentCount = 0,
    this.bufferedCount = 0,
    this.lastSentAt,
    this.lastFixAt,
    this.lat,
    this.lng,
    this.lastError,
    this.fatal = false,
  });

  factory TrackerStatus.fromJson(Map<String, dynamic> json) => TrackerStatus(
    sentCount: json['sentCount'] as int? ?? 0,
    bufferedCount: json['bufferedCount'] as int? ?? 0,
    lastSentAt: _dateFromMillis(json['lastSentAtMillis']),
    lastFixAt: _dateFromMillis(json['lastFixAtMillis']),
    lat: (json['lat'] as num?)?.toDouble(),
    lng: (json['lng'] as num?)?.toDouble(),
    lastError: json['lastError'] as String?,
    fatal: json['fatal'] as bool? ?? false,
  );

  /// Total points the backend confirmed it accepted.
  final int sentCount;

  /// Fixes held locally, waiting for the next flush or retry.
  final int bufferedCount;

  final DateTime? lastSentAt;
  final DateTime? lastFixAt;
  final double? lat;
  final double? lng;

  final String? lastError;

  /// True when the failure cannot be retried (401/403) and the service stopped
  /// itself. The user must supply a fresh token.
  final bool fatal;

  Map<String, dynamic> toJson() => {
    'sentCount': sentCount,
    'bufferedCount': bufferedCount,
    'lastSentAtMillis': lastSentAt?.millisecondsSinceEpoch,
    'lastFixAtMillis': lastFixAt?.millisecondsSinceEpoch,
    'lat': lat,
    'lng': lng,
    'lastError': lastError,
    'fatal': fatal,
  };

  static DateTime? _dateFromMillis(Object? millis) =>
      millis is int ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
}
