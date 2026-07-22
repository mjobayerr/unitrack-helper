import 'package:flutter/material.dart';

import '../config.dart';
import '../state/app_scope.dart';
import 'widgets.dart';

/// Who is signed in, what they are driving, and the way out.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Watch(
        listenable: scope.trips,
        builder: (context) {
          final trips = scope.trips;
          final bus = trips.busById(trips.activeTrip?.busId);
          final route = trips.routeById(trips.activeTrip?.routeId);

          return PageBody(
            children: [
              Center(
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    Icons.person,
                    size: 44,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                scope.session.displayName ?? 'Helper',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 26),

              Card(
                child: Column(
                  children: [
                    _Row(
                      label: 'Shift',
                      value: trips.isOnTrip ? 'On a trip' : 'Off duty',
                    ),
                    _Row(label: 'Bus', value: bus?.label ?? 'Not assigned'),
                    _Row(label: 'Route', value: route?.label ?? 'Not assigned'),
                    _Row(label: 'Server', value: AppConfig.baseUrl, last: true),
                  ],
                ),
              ),
              const SizedBox(height: 26),

              OutlinedButton.icon(
                onPressed: () => _confirmSignOut(context),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Signing out clears your PIN and this device’s saved session. '
                'You will need your email and password again.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final scope = AppScope.of(context);

    // Signing out mid-trip would leave a live trip on the server with nothing
    // reporting to it, so say so plainly rather than silently allowing it.
    final onTrip = scope.trips.isOnTrip;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          onTrip
              ? 'You are on a trip. End the trip first, or its position '
                  'updates will stop without the trip being closed.'
              : 'You will need your email and password to sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) await scope.session.signOut();
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!last) const Divider(height: 1, indent: 18, endIndent: 18),
      ],
    );
  }
}
