/// Data transfer objects mirroring the backend's Pydantic schemas.
///
/// Hand-written rather than generated from `openapi.json`, because generation
/// needs a build step in CI and there are only a handful of shapes. If this
/// grows past ~15 models, switch to `openapi-generator` — drift between these
/// and the API is a runtime crash, not a compile error.
library;

class TokenPair {
  const TokenPair({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;

  factory TokenPair.fromJson(Map<String, dynamic> json) => TokenPair(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
  );
}

class HelperProfile {
  const HelperProfile({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
  });

  final String id;
  final String name;
  final String email;
  final String? phone;

  factory HelperProfile.fromJson(Map<String, dynamic> json) => HelperProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    phone: json['phone'] as String?,
  );
}

class Bus {
  const Bus({
    required this.id,
    required this.regNo,
    required this.capacity,
    this.nickname,
  });

  final String id;
  final String regNo;
  final int capacity;
  final String? nickname;

  String get label => nickname == null ? regNo : '$regNo · $nickname';

  factory Bus.fromJson(Map<String, dynamic> json) => Bus(
    id: json['id'] as String,
    regNo: json['reg_no'] as String,
    capacity: json['capacity'] as int,
    nickname: json['nickname'] as String?,
  );
}

class BusRoute {
  const BusRoute({
    required this.id,
    required this.name,
    required this.direction,
  });

  final String id;
  final String name;
  final String direction;

  String get label => '$name · $direction';

  factory BusRoute.fromJson(Map<String, dynamic> json) => BusRoute(
    id: json['id'] as String,
    name: json['name'] as String,
    direction: json['direction'] as String,
  );
}

class Trip {
  const Trip({
    required this.id,
    required this.busId,
    required this.routeId,
    required this.status,
    this.actualStart,
    this.actualEnd,
  });

  final String id;
  final String busId;
  final String routeId;
  final String status;
  final DateTime? actualStart;
  final DateTime? actualEnd;

  Duration? get duration {
    if (actualStart == null) return null;
    return (actualEnd ?? DateTime.now().toUtc()).difference(actualStart!);
  }

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
    id: json['id'] as String,
    busId: json['bus_id'] as String,
    routeId: json['route_id'] as String,
    status: json['status'] as String,
    actualStart: _parseUtc(json['actual_start']),
    actualEnd: _parseUtc(json['actual_end']),
  );
}

/// The lighter shape returned by `GET /helper/trips/active`.
class ActiveTrip {
  const ActiveTrip({
    required this.tripId,
    required this.busId,
    required this.routeId,
  });

  final String tripId;
  final String busId;
  final String routeId;

  factory ActiveTrip.fromJson(Map<String, dynamic> json) => ActiveTrip(
    tripId: json['trip_id'] as String,
    busId: json['bus_id'] as String,
    routeId: json['route_id'] as String,
  );
}

class SeatState {
  const SeatState({
    required this.occupied,
    required this.capacity,
    required this.free,
  });

  final int occupied;
  final int capacity;
  final int free;

  factory SeatState.fromJson(Map<String, dynamic> json) => SeatState(
    occupied: json['occupied'] as int,
    capacity: json['capacity'] as int,
    free: json['free'] as int,
  );
}

/// Mirrors the backend's `AlertType` enum. The server decides severity, so it
/// is deliberately absent here — see `app/services/ops.py`.
enum AlertKind {
  sos('sos', 'SOS Emergency', 'Immediate assistance required'),
  breakdown('breakdown', 'Breakdown', 'Mechanical issue, bus stopped'),
  trafficDelay('traffic_delay', 'Traffic Delay', 'Delayed 15+ minutes'),
  accident('accident', 'Accident', 'Collision or injury'),
  overcrowding('overcrowding', 'Overcrowding', 'Bus over safe capacity');

  const AlertKind(this.wireName, this.label, this.description);

  final String wireName;
  final String label;
  final String description;
}

DateTime? _parseUtc(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toUtc();
}
