import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/api_models.dart';
import '../state/app_scope.dart';
import 'widgets.dart';

/// Report a problem. SOS is the reason this screen exists.
///
/// Reachable whether or not a trip is running — a breakdown on the way to the
/// depot is still a breakdown, and the backend accepts alerts without a trip
/// for exactly this reason.
class EmergencyPage extends StatefulWidget {
  const EmergencyPage({super.key});

  @override
  State<EmergencyPage> createState() => _EmergencyPageState();
}

class _EmergencyPageState extends State<EmergencyPage> {
  AlertKind? _sending;

  Future<void> _raise(AlertKind kind) async {
    // SOS is the one action that is genuinely dangerous to send by accident:
    // it pages a human. Everything else is a report, so it sends on one tap.
    if (kind == AlertKind.sos) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Send SOS?'),
          content: const Text(
            'This alerts the control room immediately as a critical emergency. '
            'Use it when someone is in danger.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Send SOS'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _sending = kind);
    HapticFeedback.heavyImpact();

    final trips = AppScope.of(context).trips;
    final sent = await trips.raiseAlert(kind);
    if (!mounted) return;

    setState(() => _sending = null);
    showSnack(
      context,
      sent
          ? '${kind.label} reported. The control room has been notified.'
          : (trips.error ?? 'Could not send the alert.'),
      isError: !sent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final trips = AppScope.of(context).trips;
    final theme = Theme.of(context);

    // SOS sits at the bottom, away from the thumb's resting position, so it is
    // not the button you hit while reaching for "Traffic delay".
    const ordered = [
      AlertKind.trafficDelay,
      AlertKind.overcrowding,
      AlertKind.breakdown,
      AlertKind.accident,
      AlertKind.sos,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Report a problem')),
      body: Watch(
        listenable: trips,
        builder: (context) => PageBody(
          children: [
            if (trips.error != null) ErrorBanner(message: trips.error!),
            Text(
              'Tap what is happening. The control room sees it straight away.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            for (final kind in ordered) ...[
              _AlertButton(
                kind: kind,
                busy: _sending == kind,
                enabled: _sending == null,
                onPressed: () => _raise(kind),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _AlertButton extends StatelessWidget {
  const _AlertButton({
    required this.kind,
    required this.busy,
    required this.enabled,
    required this.onPressed,
  });

  final AlertKind kind;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;

  static const _icons = {
    AlertKind.sos: Icons.sos_rounded,
    AlertKind.breakdown: Icons.car_repair,
    AlertKind.trafficDelay: Icons.traffic_outlined,
    AlertKind.accident: Icons.warning_amber_rounded,
    AlertKind.overcrowding: Icons.groups_2_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final isCritical = kind == AlertKind.sos;

    // SOS is the only filled, error-coloured control on the screen. If
    // everything shouts, nothing does.
    final background = isCritical ? scheme.error : scheme.surfaceContainer;
    final foreground = isCritical ? scheme.onError : scheme.onSurface;

    return Material(
      color: enabled ? background : background.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: busy
                    ? CircularProgressIndicator(strokeWidth: 2.5, color: foreground)
                    : Icon(_icons[kind], color: foreground, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kind.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      kind.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: foreground.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
