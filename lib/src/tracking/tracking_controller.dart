import 'dart:convert';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import '../config.dart';
import 'gps_task_handler.dart';

/// Raised when the user has not granted something the tracker needs.
class PermissionDeniedError implements Exception {
  const PermissionDeniedError(this.message, {this.openSettings = false});

  final String message;

  /// True when the denial is permanent, so a re-prompt is pointless and the
  /// user has to change it in system settings.
  final bool openSettings;

  @override
  String toString() => message;
}

/// Drives the foreground service from the UI isolate.
class TrackingController {
  const TrackingController._();

  /// Safe to call more than once.
  static void configure() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'unitrack_gps',
        channelName: 'Location sharing',
        channelDescription:
            'Shown while this phone is sending its location to UniTrack.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(AppConfig.flushIntervalMs),
        allowWakeLock: true,
        allowWifiLock: true,
        // Any stored token is good for 15 minutes, so a service resurrected
        // unattended would almost certainly wake up holding an expired one and
        // sit there failing. Tracking is started deliberately or not at all.
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowAutoRestart: false,
      ),
    );
  }

  /// Throws [PermissionDeniedError] if the tracker cannot legally run.
  static Future<void> ensurePermissions() async {
    // Android 13+: without this the service's ongoing notification — and so the
    // service itself — cannot be shown.
    var notification = await FlutterForegroundTask.checkNotificationPermission();
    if (notification != NotificationPermission.granted) {
      notification = await FlutterForegroundTask.requestNotificationPermission();
    }
    if (notification != NotificationPermission.granted) {
      throw const PermissionDeniedError(
        'Notification permission is required to run the tracker in the '
        'background.',
        openSettings: true,
      );
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const PermissionDeniedError(
        'Location is turned off on this phone. Enable it and try again.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw const PermissionDeniedError(
        'Location permission is permanently denied. Grant it in system '
        'settings to send location.',
        openSettings: true,
      );
    }
    if (permission == LocationPermission.denied) {
      throw const PermissionDeniedError('Location permission was declined.');
    }
    // whileInUse is enough: the location-typed foreground service is what keeps
    // fixes coming with the app backgrounded, so ACCESS_BACKGROUND_LOCATION is
    // not requested.
  }

  /// Starts the service, then hands it the credentials.
  static Future<void> start({
    required String token,
    required String busId,
  }) async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: 4201,
      serviceTypes: const [ForegroundServiceTypes.location],
      notificationTitle: 'UniTrack — sending location',
      notificationText: 'Starting…',
      callback: startGpsTask,
    );
    if (result is ServiceRequestFailure) {
      throw Exception('Could not start the tracker: ${result.error}');
    }

    // Belt and braces: the handler also reads these from storage in onStart,
    // because a service reporting "running" does not prove its isolate has
    // installed the task handler yet, and a push sent before that is lost.
    FlutterForegroundTask.sendDataToTask(
      jsonEncode({
        'cmd': GpsTaskHandler.configCommand,
        'token': token,
        'busId': busId,
      }),
    );
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;
}
