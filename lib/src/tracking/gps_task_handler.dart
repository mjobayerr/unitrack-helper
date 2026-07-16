import 'dart:async';
import 'dart:convert';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import '../api/gps_client.dart';
import '../config.dart';
import '../data/credential_store.dart';
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

/// Buffers GPS fixes and POSTs them to the backend every
/// [AppConfig.flushIntervalMs].
///
/// This runs in its own isolate with no access to the UI's memory, so it reads
/// the credentials from storage itself. The UI also pushes them over
/// [onReceiveData]: that arrives sooner, and covers the case where the secure
/// store is unreadable from a background isolate, but it cannot be relied on
/// alone because it may be sent before this handler is listening.
class GpsTaskHandler extends TaskHandler {
  static const String configCommand = 'config';

  static const CredentialStore _store = CredentialStore();

  GpsClient? _client;
  StreamSubscription<Position>? _positionSubscription;

  String? _token;
  String? _busId;

  final List<GpsFix> _buffer = [];
  bool _flushing = false;

  int _sentCount = 0;
  DateTime? _lastSentAt;
  DateTime? _lastFixAt;
  Position? _lastPosition;
  String? _lastError;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _client = GpsClient(baseUrl: AppConfig.baseUrl);
    await _loadStoredCredentials();
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

  /// Best-effort: plugin channels are available in this isolate, but if the
  /// secure store cannot be read here the [onReceiveData] push still supplies
  /// the credentials.
  Future<void> _loadStoredCredentials() async {
    try {
      _token ??= await _store.readToken();
      _busId ??= await _store.readBusId();
    } catch (e) {
      _lastError = 'Could not read saved credentials: $e';
    }
  }

  @override
  void onReceiveData(Object data) {
    if (data is! String) return;
    final message = jsonDecode(data) as Map<String, dynamic>;
    if (message['cmd'] != configCommand) return;

    // The UI is the fresher source — let it win over whatever was stored.
    _token = message['token'] as String? ?? _token;
    _busId = message['busId'] as String? ?? _busId;
    if (_token != null && _busId != null) {
      _lastError = null;
    }
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
    _client?.close();
  }

  void _onPosition(Position position) {
    _lastPosition = position;
    _lastFixAt = DateTime.now();
    _buffer.add(GpsFix.fromPosition(position));
    _trimBuffer();
  }

  /// Keeps the newest [AppConfig.maxBatchSize] fixes. Older ones are dropped:
  /// a stale position is worth less than staying inside the backend's limit,
  /// and this app has no offline store yet.
  void _trimBuffer() {
    if (_buffer.length > AppConfig.maxBatchSize) {
      _buffer.removeRange(0, _buffer.length - AppConfig.maxBatchSize);
    }
  }

  Future<void> _flush() async {
    if (_flushing) return;

    final token = _token;
    final busId = _busId;
    if (token == null || busId == null) {
      _lastError = 'Waiting for credentials from the app';
      _report();
      return;
    }
    if (_buffer.isEmpty) {
      _report();
      return;
    }

    _flushing = true;
    // Take the batch out of the buffer up front. Fixes keep arriving during the
    // request, and _trimBuffer can drop from the front, so a prefix removed
    // after the await is no longer guaranteed to be the batch we sent.
    final batch = _buffer.take(AppConfig.maxBatchSize).toList();
    _buffer.removeRange(0, batch.length);
    try {
      final accepted = await _client!.sendBatch(
        token: token,
        busId: busId,
        fixes: batch,
      );
      _sentCount += accepted;
      _lastSentAt = DateTime.now();
      _lastError = null;
      _report();
    } on GpsAuthException catch (e) {
      // Unretryable. Stop rather than burn battery posting into a 401.
      _lastError = '${e.message}. Tracking stopped — paste a fresh token.';
      _report(fatal: true);
      await FlutterForegroundTask.stopService();
    } catch (e) {
      // Retryable: put the batch back ahead of the newer fixes and try again on
      // the next tick.
      _buffer.insertAll(0, batch);
      _trimBuffer();
      _lastError = e.toString();
      _report();
    } finally {
      _flushing = false;
    }
  }

  void _report({bool fatal = false}) {
    final status = TrackerStatus(
      sentCount: _sentCount,
      bufferedCount: _buffer.length,
      lastSentAt: _lastSentAt,
      lastFixAt: _lastFixAt,
      lat: _lastPosition?.latitude,
      lng: _lastPosition?.longitude,
      lastError: _lastError,
      fatal: fatal,
    );
    FlutterForegroundTask.sendDataToMain(jsonEncode(status.toJson()));

    FlutterForegroundTask.updateService(
      notificationTitle: 'UniTrack — sending location',
      notificationText: _lastError != null
          ? 'Problem: $_lastError'
          : 'Sent $_sentCount points · ${_buffer.length} queued',
    );
  }
}
