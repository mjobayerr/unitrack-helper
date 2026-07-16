import 'package:geolocator/geolocator.dart';

/// One GPS fix, shaped to the backend's `GpsPointIn` schema.
class GpsFix {
  const GpsFix({
    required this.lat,
    required this.lng,
    required this.ts,
    this.speed,
    this.heading,
    this.accuracy,
  });

  factory GpsFix.fromPosition(Position p) => GpsFix(
    lat: p.latitude,
    lng: p.longitude,
    ts: p.timestamp,
    speed: p.speed,
    heading: p.heading,
    accuracy: p.accuracy,
  );

  final double lat;
  final double lng;
  final DateTime ts;
  final double? speed;
  final double? heading;
  final double? accuracy;

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    // Backend reads this as the device clock and normalises to UTC itself.
    'ts': ts.toUtc().toIso8601String(),
    'speed': speed,
    'heading': heading,
    'accuracy': accuracy,
  };
}
