import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'src/api/api_client.dart';
import 'src/app.dart';
import 'src/state/session_controller.dart';
import 'src/state/trip_controller.dart';
import 'src/tracking/tracking_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Opens the port the service isolate reports status on. Must run before the
  // first frame, and before any service is started.
  FlutterForegroundTask.initCommunicationPort();
  TrackingController.configure();

  // Built once here and handed down, so a hot reload cannot quietly create a
  // second ApiClient with its own token-refresh state.
  final api = ApiClient();
  final session = SessionController(api: api);
  final trips = TripController(api: api);

  // Decides the opening screen from what is already on the device. The router
  // shows a spinner until this resolves.
  session.bootstrap();

  runApp(UniTrackHelperApp(session: session, trips: trips));
}
