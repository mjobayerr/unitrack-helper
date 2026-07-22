import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../state/app_scope.dart';
import '../theme/app_theme.dart';
import 'widgets.dart';

/// The screen the helper looks at all day.
///
/// Two states, deliberately not two pages: off duty (one big Start Trip button)
/// and on a trip (live status, counts, actions). Splitting them would let the
/// two drift apart, and the transition between them is the app's main event.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  void initState() {
    super.initState();
    // The server decides whether a trip is live, not this app: it may have been
    // killed mid-route, or ended from elsewhere.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scope = AppScope.of(context);
      scope.trips.restore();
      scope.trips.loadFleet();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Watch(
          listenable: scope.session,
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'UniTrack',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              if (scope.session.displayName != null)
                Text(
                  scope.session.displayName!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile',
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: Watch(
        listenable: scope.trips,
        builder: (context) {
          final trips = scope.trips;
          final onTrip = trips.isOnTrip;
          final bus = trips.busById(trips.activeTrip?.busId);
          final route = trips.routeById(trips.activeTrip?.routeId);
          final seats = trips.seats;

          return RefreshIndicator(
            onRefresh: () async {
              await trips.restore();
              await trips.loadFleet();
            },
            child: PageBody(
              children: [
                if (trips.error != null) ErrorBanner(message: trips.error!),

                // --- status card ---
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                onTrip ? 'Trip active' : 'Off duty',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            StatusChip(
                              label: onTrip ? 'On route' : 'Idle',
                              color: onTrip
                                  ? AppTheme.success
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              onTrip
                                  ? Icons.location_on
                                  : Icons.location_off_outlined,
                              size: 16,
                              color: onTrip
                                  ? AppTheme.success
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              onTrip
                                  ? 'Live tracking on'
                                  : 'Tracking off',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: onTrip
                                    ? AppTheme.success
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        if (onTrip) ...[
                          const SizedBox(height: 16),
                          _InfoRow(
                            icon: Icons.directions_bus_outlined,
                            label: 'Bus',
                            value: bus?.label ?? '—',
                          ),
                          const SizedBox(height: 8),
                          _InfoRow(
                            icon: Icons.route_outlined,
                            label: 'Route',
                            value: route?.label ?? '—',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                if (onTrip) ...[
                  ResponsiveRow(
                    children: [
                      StatTile(
                        label: 'Passengers',
                        value: seats == null ? '—' : '${seats.occupied}',
                        suffix: seats == null ? null : '/ ${seats.capacity}',
                        onTap: () => context.push('/counter'),
                      ),
                      StatTile(
                        label: 'Seats free',
                        value: seats == null ? '—' : '${seats.free}',
                        accent: AppTheme.success,
                        onTap: () => context.push('/counter'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/counter'),
                    icon: const Icon(Icons.groups_outlined),
                    label: const Text('Update passenger count'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/emergency'),
                    icon: const Icon(Icons.warning_amber_rounded),
                    label: const Text('Report a problem'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: trips.busy ? null : () => _confirmEnd(context),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('END TRIP'),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.errorContainer,
                      foregroundColor: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ] else ...[
                  FilledButton.icon(
                    onPressed: trips.busy
                        ? null
                        : () => context.push('/start-trip'),
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('START TRIP'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/emergency'),
                    icon: const Icon(Icons.warning_amber_rounded),
                    label: const Text('Report a problem'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// Ending a trip stops tracking and cannot be undone from the app, so it asks.
  Future<void> _confirmEnd(BuildContext context) async {
    final trips = AppScope.of(context).trips;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this trip?'),
        content: const Text(
          'Location sharing stops and the trip is closed. '
          'Start a new trip to begin tracking again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End trip'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final ended = await trips.endTrip();
    if (!context.mounted) return;
    showSnack(
      context,
      ended ? 'Trip ended.' : (trips.error ?? 'Could not end the trip.'),
      isError: !ended,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Text(
          '$label  ',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
