import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_scope.dart';
import '../theme/app_theme.dart';
import 'widgets.dart';

/// Passenger tally.
///
/// Big plus and minus keys, because this is tapped while the bus is moving and
/// people are boarding. The count is only sent when the helper confirms, so a
/// mis-tap costs nothing and the backend does not receive a row per tap.
class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  int _count = 0;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    // Start from the last reported figure so the helper adjusts rather than
    // recounts from zero.
    _count = AppScope.of(context).trips.seats?.occupied ?? 0;
  }

  void _bump(int delta) {
    final capacityGuard = _count + delta;
    if (capacityGuard < 0) return;
    HapticFeedback.selectionClick();
    setState(() {
      _count = capacityGuard;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final trips = AppScope.of(context).trips;
    await trips.reportSeats(_count);
    if (!mounted) return;

    final failed = trips.error != null;
    showSnack(
      context,
      failed ? trips.error! : 'Passenger count updated.',
      isError: failed,
    );
    if (!failed) setState(() => _dirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final trips = AppScope.of(context).trips;
    final theme = Theme.of(context);
    final capacity = trips.busById(trips.activeTrip?.busId)?.capacity;
    final free = capacity == null ? null : (capacity - _count).clamp(0, capacity);
    final over = capacity != null && _count > capacity;

    return Scaffold(
      appBar: AppBar(title: const Text('Passengers')),
      body: Watch(
        listenable: trips,
        builder: (context) => PageBody(
          children: [
            if (trips.error != null) ErrorBanner(message: trips.error!),

            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                child: Column(
                  children: [
                    Text(
                      'ON BOARD',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: context.cappedTextScaler),
                      child: Text(
                        '$_count',
                        style: theme.textTheme.displayLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1,
                          color: over
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      capacity == null
                          ? 'Capacity unknown'
                          : over
                              ? 'Over capacity by ${_count - capacity}'
                              : '$free of $capacity seats free',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: over
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: over ? FontWeight.w700 : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            ResponsiveRow(
              children: [
                _BigKey(
                  icon: Icons.remove,
                  label: 'Got off',
                  onPressed: _count == 0 ? null : () => _bump(-1),
                ),
                _BigKey(
                  icon: Icons.add,
                  label: 'Got on',
                  accent: AppTheme.success,
                  onPressed: () => _bump(1),
                ),
              ],
            ),
            const SizedBox(height: 24),

            FilledButton(
              onPressed: (!_dirty || trips.busy) ? null : _save,
              child: Text(_dirty ? 'SAVE COUNT' : 'SAVED'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _count == 0 ? null : () => setState(() {
                _count = 0;
                _dirty = true;
              }),
              child: const Text('Reset to zero'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tap target sized for a moving vehicle — far past the 48dp minimum.
class _BigKey extends StatelessWidget {
  const _BigKey({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.accent,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? scheme.primary;
    final enabled = onPressed != null;

    return Material(
      color: enabled
          ? color.withValues(alpha: 0.14)
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          height: 108,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 36,
                color: enabled ? color : scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: enabled ? color : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
