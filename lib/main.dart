import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

void main() => runApp(const HelperApp());

class HelperApp extends StatelessWidget {
  const HelperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UniTrack Helper',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const GpsSenderPage(),
    );
  }
}

class GpsSenderPage extends StatefulWidget {
  const GpsSenderPage({super.key});

  @override
  State<GpsSenderPage> createState() => _GpsSenderPageState();
}

class _GpsSenderPageState extends State<GpsSenderPage> {
  final List<Position> _buffer = [];
  StreamSubscription<Position>? _posSub;
  Timer? _timer;

  bool _running = false;
  Position? _last;
  int _sent = 0; // total points the backend accepted
  int? _lastStatus;
  String? _error;

  /// Ensure location services are on and permission is granted.
  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => _error = 'Location services are off on this device.');
      return false;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      setState(() => _error = 'Location permission denied.');
      return false;
    }
    return true;
  }

  Future<void> _start() async {
    if (!await _ensurePermission()) return;
    setState(() {
      _error = null;
      _running = true;
    });

    _posSub = Geolocator.getPositionStream(
      locationSettings:
          const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 0),
    ).listen((pos) {
      _buffer.add(pos);
      setState(() => _last = pos);
    });

    _timer = Timer.periodic(Config.flushInterval, (_) => _flush());
  }

  Future<void> _stop() async {
    await _posSub?.cancel();
    _timer?.cancel();
    _posSub = null;
    _timer = null;
    setState(() => _running = false);
  }

  /// POST buffered fixes to the backend. On failure, points are put back so the
  /// next tick retries (offline-first spirit — spec §7.3).
  Future<void> _flush() async {
    if (_buffer.isEmpty) return;

    // GpsBatch caps at 50 points per request.
    final batch = _buffer.take(50).toList();
    _buffer.removeRange(0, batch.length);

    final body = jsonEncode({
      'bus_id': Config.busId,
      'points': [
        for (final p in batch)
          {
            'lat': p.latitude,
            'lng': p.longitude,
            'ts': p.timestamp.toUtc().toIso8601String(),
            'speed': p.speed,
            'heading': p.heading,
            'accuracy': p.accuracy,
          }
      ],
    });

    try {
      final res = await http.post(
        Uri.parse('${Config.apiBase}/helper/gps'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${Config.helperToken}',
        },
        body: body,
      );
      if (!mounted) return;
      setState(() {
        _lastStatus = res.statusCode;
        if (res.statusCode == 202) {
          _sent += (jsonDecode(res.body)['accepted'] as int);
          _error = null;
        } else {
          _error = res.body;
          _buffer.insertAll(0, batch); // retry next tick
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _buffer.insertAll(0, batch); // retry next tick
      });
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _last;
    return Scaffold(
      appBar: AppBar(title: const Text('UniTrack Helper — GPS')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Backend', Config.apiBase),
            _row('Bus', Config.busId),
            const Divider(height: 32),
            _row('Position',
                p == null ? '—' : '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}'),
            _row('Accuracy', p == null ? '—' : '±${p.accuracy.toStringAsFixed(0)} m'),
            _row('Buffered', '${_buffer.length}'),
            _row('Accepted', '$_sent'),
            _row('Last HTTP', _lastStatus?.toString() ?? '—'),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _running ? _stop : _start,
                child: Text(_running ? 'Stop' : 'Start sending'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 100, child: Text(k, style: const TextStyle(color: Colors.grey))),
            Expanded(child: Text(v, style: const TextStyle(fontFamily: 'monospace'))),
          ],
        ),
      );
}
