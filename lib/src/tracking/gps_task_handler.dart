import 'dart:async';
import 'dart:convert';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import '../api/api_client.dart';
import '../config.dart';
import '../data/credential_store.dart';
import '../data/gps_queue.dart';
import '../models/gps_fix.dart';
import '../models/tracker_status.dart';

/// Entry point for the foreground service isolate.
///
/// Must stay top-level and keep the `vm:entry-point` pragma, otherwise tree
/// shaking drops it from release builds and the service starts into nothing.
@pragma('vm:entry-point')
void startGpsTask() {
  FlutterForegroundTask.setTaskHandler(GpsTaskHandler());
}

/// Streams GPS fixes to the backend for the length of a trip.
///
/// Runs in its own isolate with no access to the UI's memory. Two things make
/// it survive a real route rather than a demo:
///
/// **It refreshes its own token.** It talks through [ApiClient], which retries
/// once on a 401 using the refresh token in shared secure storage. The previous
/// version was handed a 15-minute access token it could not renew, so tracking
/// stopped 15 minutes into every trip.
///
/// **It buffers to disk.** Fixes go into [GpsQueue] (SQLite) the moment they
/// arrive and are deleted only once the backend has accepted them. Killing the
/// app in a coverage blackspot no longer loses the route.
class GpsTaskHandler extends TaskHandler {
  static const String configCommand = 'config';

  static const CredentialStore _store = CredentialStore();

  ApiClient? _api;
  GpsQueue? _queue;
  StreamSubscription<Position>? _positionSubscription;

  String? _busId;
  bool _flushing = false;

  int _sentCount = 0;
  DateTime? _lastSentAt;
  DateTime? _lastFixAt;
  Position? _lastPosition;
  String? _lastError;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _api = ApiClient();
    try {
      _queue = await GpsQueue.open();
    } catch (e) {
      // Without the queue we would silently drop every fix, so say so loudly
      // rather than appear to be tracking.
      _lastError = 'Could not open the local buffer: $e';
    }

    // The UI also pushes this over onReceiveData, which arrives sooner. Reading
    // it here covers the case where the push was sent before this handler was
    // listening — a service reporting "running" does not prove its isolate is
    // ready.
    _busId ??= await _readBusId();

    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: AppConfig.distanceFilterMeters,
          ),
        ).listen(
          _onPosition,
          onError: (Object error) {
            _lastError = 'Location stream failed: $error';
            _report();
          },
        );
    _report();
  }

  Future<String?> _readBusId() async {
    try {
      return await _store.readBusId();
    } catch (e) {
      _lastError = 'Could not read the saved bus id: $e';
      return null;
    }
  }

  @override
  void onReceiveData(Object data) {
    if (data is! String) return;
    final message = jsonDecode(data) as Map<String, dynamic>;
    if (message['cmd'] != configCommand) return;

    // The UI is the fresher source — let it win over whatever was stored.
    _busId = message['busId'] as String? ?? _busId;
    if (_busId != null) _lastError = null;
    _report();
  }

  /// Fires on the [AppConfig.flushIntervalMs] tick set in `ForegroundTaskOptions`.
  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_flush());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _positionSubscription?.cancel();
    // One last attempt, so fixes taken since the previous tick are not stranded
    // in the queue until the next trip.
    await _flush();
    await _queue?.close();
    _api?.close();
  }

  Future<void> _onPosition(Position position) async {
    _lastPosition = position;
    _lastFixAt = DateTime.now();
    try {
      await _queue?.add(GpsFix.fromPosition(position));
    } catch (e) {
      _lastError = 'Could not buffer a fix: $e';
    }
  }

  Future<void> _flush() async {
    if (_flushing) return;

    final api = _api;
    final queue = _queue;
    final busId = _busId;
    if (api == null || queue == null) return;
    if (busId == null) {
      _lastError = 'Waiting for the trip details from the app';
      _report();
      return;
    }

    _flushing = true;
    try {
      // Peek rather than take: the rows stay in the database until the backend
      // has acknowledged them, so a crash mid-request costs a duplicate rather
      // than a hole in the route. The backend indexes by stream id and is
      // idempotent, so duplicates are free.
      final batch = await queue.peek(AppConfig.maxBatchSize);
      if (batch.isEmpty) {
        _report();
        return;
      }

      final accepted = await api.postGps(
        busId: busId,
        fixes: [for (final queued in batch) queued.fix],
      );
      await queue.ackThrough(batch.last.id);

      _sentCount += accepted;
      _lastSentAt = DateTime.now();
      _lastError = null;
      _report();
    } on SessionExpiredException {
      // The refresh token itself is dead — signed out, revoked or suspended.
      // No amount of retrying fixes that, and continuing would drain the
      // battery posting into a 401.
      _lastError = 'Session expired. Sign in again to keep tracking.';
      _report(fatal: true);
      await FlutterForegroundTask.stopService();
    } on ApiException catch (e) {
      if (e.statusCode == 403) {
        // Approval revoked, or this account may not post for this bus.
        _lastError = '${e.message}. Tracking stopped.';
        _report(fatal: true);
        await FlutterForegroundTask.stopService();
      } else {
        // 404, 409, 5xx — leave the batch queued and try again next tick.
        _lastError = e.message;
        _report();
      }
    } catch (e) {
      // Offline, DNS failure, timeout. The queue keeps the fixes; this is the
      // case the durable buffer exists for.
      _lastError = 'Offline — fixes are being saved on the phone.';
      _report();
    } finally {
      _flushing = false;
    }
  }

  Future<void> _report({bool fatal = false}) async {
    final queued = await _safeQueueCount();
    final status = TrackerStatus(
      sentCount: _sentCount,
      bufferedCount: queued,
      lastSentAt: _lastSentAt,
      lastFixAt: _lastFixAt,
      lat: _lastPosition?.latitude,
      lng: _lastPosition?.longitude,
      lastError: _lastError,
      fatal: fatal,
    );
    FlutterForegroundTask.sendDataToMain(jsonEncode(status.toJson()));

    FlutterForegroundTask.updateService(
      notificationTitle: 'UniTrack — sharing location',
      notificationText: _lastError != null
          ? _lastError!
          : 'Sent $_sentCount · $queued waiting',
    );
  }

  Future<int> _safeQueueCount() async {
    try {
      return await _queue?.count() ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
