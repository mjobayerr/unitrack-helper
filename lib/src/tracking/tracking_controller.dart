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
        // If the OS kills the service — the guaranteed outcome on OEM phones
        // (Xiaomi, Realme, Samsung) with battery optimisation on — restart it.
        // On restart the handler reads the bus id and refresh token from
        // storage and resumes the still-live trip. This was previously off
        // because the isolate held a 15-minute access token it could not renew;
        // now it refreshes its own token, so a resurrected service works.
        allowAutoRestart: true,
        // Reinstall / update should also bring tracking back mid-shift.
        autoRunOnMyPackageReplaced: true,
        // Boot stays off: a phone rebooting is not a helper starting a shift,
        // and tracking must begin from a deliberate Start Trip, not silently.
        autoRunOnBoot: false,
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

    // The real-world reason tracking dies on a swipe-away: OEM battery
    // managers (Xiaomi, Realme, Oppo, Samsung — most of the Bangladeshi
    // market) kill background services aggressively unless the app is exempt.
    // This asks the system to stop doing that. Best-effort: if the helper
    // declines, tracking still works while the app is open, so a refusal must
    // not block starting a trip — it only makes a swipe-away less reliable.
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  /// Starts the service, then tells it which bus it is tracking.
  ///
  /// No token is passed: the isolate reads the session from shared secure
  /// storage and refreshes it itself. Handing it a 15-minute access token was
  /// what made tracking die mid-route.
  static Future<void> start({required String busId}) async {
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

    // Belt and braces: the handler also reads this from storage in onStart,
    // because a service reporting "running" does not prove its isolate has
    // installed the task handler yet, and a push sent before that is lost.
    FlutterForegroundTask.sendDataToTask(
      jsonEncode({'cmd': GpsTaskHandler.configCommand, 'busId': busId}),
    );
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;
}
