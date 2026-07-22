import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../data/session_store.dart';
import '../models/api_models.dart';
import '../tracking/tracking_controller.dart';

/// Owns the live trip and everything hanging off it.
///
/// The trip is the app's central fact: tracking runs only during one, seat
/// counts and alerts attach to one, and the dashboard is mostly a rendering of
/// it. Keeping that in one notifier means the screens never disagree about
/// whether a trip is running.
class TripController extends ChangeNotifier {
  TripController({required ApiClient api, SessionStore store = const SessionStore()})
    : _api = api,
      _store = store;

  final ApiClient _api;
  final SessionStore _store;

  ActiveTrip? _activeTrip;
  SeatState? _seats;
  List<Bus> _buses = const [];
  List<BusRoute> _routes = const [];
  Trip? _lastEndedTrip;
  String? _error;
  bool _busy = false;

  ActiveTrip? get activeTrip => _activeTrip;
  bool get isOnTrip => _activeTrip != null;
  SeatState? get seats => _seats;
  List<Bus> get buses => _buses;
  List<BusRoute> get routes => _routes;
  Trip? get lastEndedTrip => _lastEndedTrip;
  String? get error => _error;
  bool get busy => _busy;

  Bus? busById(String? id) =>
      _buses.where((b) => b.id == id).firstOrNull;
  BusRoute? routeById(String? id) =>
      _routes.where((r) => r.id == id).firstOrNull;

  /// Restores state after a launch, crash or force-stop.
  ///
  /// The server is the authority on whether a trip is live, not the phone: the
  /// helper may have ended the trip from another device, or the app may have
  /// been killed mid-trip. If a trip *is* live, tracking is restarted, because
  /// a live trip that is not sending positions is the worst possible state —
  /// the map shows a bus frozen where it was when the app died.
  Future<void> restore() async {
    await _guard(() async {
      _activeTrip = await _api.activeTrip();
      if (_activeTrip != null && !await TrackingController.isRunning) {
        await _startTracking(_activeTrip!.busId);
      }
    });
  }

  /// Loads the bus and route pickers. Cheap and rarely changing, so it is
  /// fetched once when the start-trip screen opens rather than kept in sync.
  Future<void> loadFleet() async {
    await _guard(() async {
      final results = await Future.wait([_api.buses(), _api.routes()]);
      _buses = results[0] as List<Bus>;
      _routes = results[1] as List<BusRoute>;
    });
  }

  Future<bool> startTrip({required String busId, required String routeId}) async {
    var started = false;
    await _guard(() async {
      final trip = await _api.startTrip(busId: busId, routeId: routeId);
      _activeTrip = ActiveTrip(
        tripId: trip.id,
        busId: trip.busId,
        routeId: trip.routeId,
      );
      // Tracking starts only after the server has accepted the trip, so fixes
      // can never be queued against a trip that does not exist.
      await _startTracking(trip.busId);
      started = true;
    });
    return started;
  }

  Future<bool> endTrip() async {
    var ended = false;
    await _guard(() async {
      // Stop the sensor first: a fix captured between the end call and the
      // service stopping would belong to a completed trip.
      await TrackingController.stop();
      _lastEndedTrip = await _api.endTrip();
      _activeTrip = null;
      _seats = null;
      ended = true;
    });
    return ended;
  }

  Future<void> reportSeats(int occupied) async {
    await _guard(() async {
      _seats = await _api.reportSeats(occupied);
    });
  }

  /// Raises an alert.
  ///
  /// Position is omitted for now: the last fix lives in the service isolate and
  /// only reaches the UI through the status channel, which the dashboard does
  /// not yet subscribe to. The backend already accepts a null lat/lng, and an
  /// SOS without coordinates is far better than an SOS that fails to send.
  // TODO(helper): attach lat/lng once the dashboard consumes TrackerStatus.
  Future<bool> raiseAlert(AlertKind kind, {String? message}) async {
    var sent = false;
    await _guard(() async {
      await _api.raiseAlert(kind, message: message);
      sent = true;
    });
    return sent;
  }

  /// Hands the service the credentials it needs.
  ///
  /// Known limitation: the isolate receives a 15-minute access token and has no
  /// way to refresh it, so tracking still dies mid-route on a long trip. Fixing
  /// it properly means moving the refresh into the task handler and having it
  /// drain the durable outbox — that is the next piece of work, and it is why
  /// GpsQueue exists but is not yet wired in.
  Future<void> _startTracking(String busId) async {
    final token = await _store.readAccessToken();
    if (token == null) throw const SessionExpiredException();
    await TrackingController.start(token: token, busId: busId);
  }

  Future<void> _guard(Future<void> Function() action) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
    } on ApiException catch (e) {
      _error = e.message;
    } on SessionExpiredException {
      rethrow; // The session layer owns this; do not swallow it into a banner.
    } catch (e) {
      _error = 'Cannot reach the server.';
      debugPrint('trip action failed: $e');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
