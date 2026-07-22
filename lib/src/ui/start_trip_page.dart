import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/api_models.dart';
import '../state/app_scope.dart';
import '../tracking/tracking_controller.dart';
import 'widgets.dart';

/// Pick a bus and a route, then go.
///
/// Both are dropdowns fed by `/fleet/*`. The previous build made the helper
/// type a bus UUID by hand, which is unusable on a phone and silently wrong
/// when mistyped.
class StartTripPage extends StatefulWidget {
  const StartTripPage({super.key});

  @override
  State<StartTripPage> createState() => _StartTripPageState();
}

class _StartTripPageState extends State<StartTripPage> {
  String? _busId;
  String? _routeId;
  String? _permissionError;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppScope.of(context).trips.loadFleet();
    });
  }

  Future<void> _start() async {
    final trips = AppScope.of(context).trips;
    if (_busId == null || _routeId == null) return;

    setState(() {
      _starting = true;
      _permissionError = null;
    });

    try {
      // Ask before creating the trip. Starting a trip we then cannot track
      // would leave a live trip on the server with no positions behind it.
      await TrackingController.ensurePermissions();
    } on PermissionDeniedError catch (e) {
      setState(() {
        _starting = false;
        _permissionError = e.message;
      });
      return;
    }

    final ok = await trips.startTrip(busId: _busId!, routeId: _routeId!);
    if (!mounted) return;
    setState(() => _starting = false);

    if (ok) {
      showSnack(context, 'Trip started. Location sharing is on.');
      context.go('/dashboard');
    } else {
      showSnack(context, trips.error ?? 'Could not start the trip.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trips = AppScope.of(context).trips;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Start a trip')),
      body: Watch(
        listenable: trips,
        builder: (context) {
          final ready = _busId != null && _routeId != null && !_starting;

          return PageBody(
            children: [
              if (_permissionError != null)
                ErrorBanner(message: _permissionError!),
              if (trips.error != null) ErrorBanner(message: trips.error!),

              Text(
                'Which bus are you on?',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _busId,
                isExpanded: true, // Long names ellipsize instead of overflowing.
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.directions_bus_outlined),
                  hintText: 'Select a bus',
                ),
                items: [
                  for (final Bus bus in trips.buses)
                    DropdownMenuItem(value: bus.id, child: Text(bus.label)),
                ],
                onChanged: (v) => setState(() => _busId = v),
              ),
              const SizedBox(height: 22),

              Text(
                'Which route?',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _routeId,
                isExpanded: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.route_outlined),
                  hintText: 'Select a route',
                ),
                items: [
                  for (final BusRoute route in trips.routes)
                    DropdownMenuItem(value: route.id, child: Text(route.label)),
                ],
                onChanged: (v) => setState(() => _routeId = v),
              ),

              if (trips.buses.isEmpty && !trips.busy) ...[
                const SizedBox(height: 20),
                Text(
                  'No buses available. Ask an admin to add one.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],

              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: ready ? _start : null,
                icon: _starting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Icon(Icons.play_circle_outline),
                label: Text(_starting ? 'STARTING…' : 'START TRIP'),
              ),
              const SizedBox(height: 12),
              Text(
                'Your phone shares its location until you end the trip. '
                'A notification stays visible while it does.',
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
}
