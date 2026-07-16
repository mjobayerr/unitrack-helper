import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../config.dart';
import '../data/credential_store.dart';
import '../models/tracker_status.dart';
import '../tracking/tracking_controller.dart';

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _store = CredentialStore();

  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();
  final _busIdController = TextEditingController();

  TrackerStatus _status = const TrackerStatus();
  bool _running = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    TrackingController.configure();
    _restore();
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _tokenController.dispose();
    _busIdController.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final token = await _store.readToken();
    final busId = await _store.readBusId();
    final running = await TrackingController.isRunning;
    if (!mounted) return;
    setState(() {
      _tokenController.text = token ?? '';
      _busIdController.text = busId ?? '';
      _running = running;
    });
  }

  void _onTaskData(Object data) {
    if (data is! String) return;
    final status = TrackerStatus.fromJson(
      jsonDecode(data) as Map<String, dynamic>,
    );
    if (!mounted) return;
    setState(() {
      _status = status;
      // The handler stops itself on 401/403; reflect that instead of showing a
      // Stop button for a service that is already gone.
      if (status.fatal) _running = false;
    });
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_running) {
        await TrackingController.stop();
        if (mounted) setState(() => _running = false);
      } else {
        await _start();
      }
    } catch (e) {
      _showError(e is PermissionDeniedError ? e.message : e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final token = _tokenController.text.trim();
    final busId = _busIdController.text.trim();

    await TrackingController.ensurePermissions();
    await _store.writeToken(token);
    await _store.writeBusId(busId);
    await TrackingController.start(token: token, busId: busId);

    if (!mounted) return;
    setState(() {
      _running = true;
      _status = const TrackerStatus();
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the app alive in the background when the back button is pressed
    // while the service runs.
    return WithForegroundTask(
      child: Scaffold(
        appBar: AppBar(title: const Text('UniTrack Helper')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _CredentialsForm(
                formKey: _formKey,
                tokenController: _tokenController,
                busIdController: _busIdController,
                enabled: !_running,
              ),
              const SizedBox(height: 24),
              _StatusCard(status: _status, running: _running),
              const SizedBox(height: 24),
              _ToggleButton(
                running: _running,
                busy: _busy,
                onPressed: _toggle,
              ),
              const SizedBox(height: 12),
              Text(
                'Backend: ${AppConfig.baseUrl}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CredentialsForm extends StatelessWidget {
  const _CredentialsForm({
    required this.formKey,
    required this.tokenController,
    required this.busIdController,
    required this.enabled,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController tokenController;
  final TextEditingController busIdController;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        children: [
          TextFormField(
            controller: busIdController,
            enabled: enabled,
            decoration: const InputDecoration(
              labelText: 'Bus ID',
              hintText: '00000000-0000-0000-0000-000000000000',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return 'Enter the bus ID';
              // Checked here so a typo shows up as a field error rather than a
              // 422 five seconds into tracking.
              if (!_uuidPattern.hasMatch(text)) return 'Not a valid UUID';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: tokenController,
            enabled: enabled,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Access token',
              helperText: 'From POST /auth/login. Expires after 15 minutes.',
              border: OutlineInputBorder(),
            ),
            validator: (value) =>
                (value?.trim().isEmpty ?? true) ? 'Paste an access token' : null,
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.running});

  final TrackerStatus status;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = status.lastError;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  running ? Icons.location_on : Icons.location_off,
                  color: running ? Colors.green : theme.disabledColor,
                ),
                const SizedBox(width: 8),
                Text(
                  running ? 'Sending location' : 'Stopped',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const Divider(height: 24),
            _Row(label: 'Points accepted', value: '${status.sentCount}'),
            _Row(label: 'Queued', value: '${status.bufferedCount}'),
            _Row(label: 'Last fix', value: _position(status)),
            _Row(label: 'Last sent', value: _time(status.lastSentAt)),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _position(TrackerStatus status) {
    final lat = status.lat;
    final lng = status.lng;
    if (lat == null || lng == null) return '—';
    return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }

  static String _time(DateTime? value) {
    if (value == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.running,
    required this.busy,
    required this.onPressed,
  });

  final bool running;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: FilledButton.icon(
        onPressed: busy ? null : onPressed,
        style: running
            ? FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              )
            : null,
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(running ? Icons.stop : Icons.play_arrow),
        label: Text(running ? 'Stop' : 'Start'),
      ),
    );
  }
}
