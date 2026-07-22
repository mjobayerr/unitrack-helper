import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'state/app_scope.dart';
import 'state/session_controller.dart';
import 'state/trip_controller.dart';
import 'theme/app_theme.dart';
import 'ui/counter_page.dart';
import 'ui/dashboard_page.dart';
import 'ui/emergency_page.dart';
import 'ui/login_page.dart';
import 'ui/pin_page.dart';
import 'ui/profile_page.dart';
import 'ui/start_trip_page.dart';

class UniTrackHelperApp extends StatefulWidget {
  const UniTrackHelperApp({
    super.key,
    required this.session,
    required this.trips,
  });

  final SessionController session;
  final TripController trips;

  @override
  State<UniTrackHelperApp> createState() => _UniTrackHelperAppState();
}

class _UniTrackHelperAppState extends State<UniTrackHelperApp> {
  late final GoRouter _router = _buildRouter();

  GoRouter _buildRouter() {
    return GoRouter(
      initialLocation: '/',
      // Re-evaluates every redirect whenever the session changes, so signing
      // out or a dead refresh token bounces the user to /login from wherever
      // they are. Without this each page would need its own guard, and the one
      // that gets forgotten is the one that leaks.
      refreshListenable: widget.session,
      redirect: (context, state) {
        final session = widget.session.state;
        final path = state.matchedLocation;

        if (session == SessionState.unknown) {
          return path == '/' ? null : '/';
        }
        if (session == SessionState.signedOut) {
          return path == '/login' ? null : '/login';
        }
        // needsPin: signed in but no PIN chosen yet. locked: PIN exists but has
        // not been entered. Both land on the same page in different modes.
        if (session == SessionState.needsPin || session == SessionState.locked) {
          return path == '/pin' ? null : '/pin';
        }
        // Signed in and unlocked — keep them out of the auth screens.
        if (path == '/' || path == '/login' || path == '/pin') {
          return '/dashboard';
        }
        return null;
      },
      routes: [
        GoRoute(path: '/', builder: (_, _) => const _SplashPage()),
        GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
        GoRoute(path: '/pin', builder: (_, _) => const PinPage()),
        GoRoute(path: '/dashboard', builder: (_, _) => const DashboardPage()),
        GoRoute(path: '/start-trip', builder: (_, _) => const StartTripPage()),
        GoRoute(path: '/counter', builder: (_, _) => const CounterPage()),
        GoRoute(path: '/emergency', builder: (_, _) => const EmergencyPage()),
        GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      session: widget.session,
      trips: widget.trips,
      child: MaterialApp.router(
        title: 'UniTrack Helper',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        // The helper works in direct sun and in a dark cabin; the system
        // setting is the only thing that knows which.
        themeMode: ThemeMode.system,
        routerConfig: _router,
      ),
    );
  }
}

/// Shown for the moment it takes to read the token store and decide where to go.
class _SplashPage extends StatelessWidget {
  const _SplashPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
