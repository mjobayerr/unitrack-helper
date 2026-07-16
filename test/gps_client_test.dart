import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:unitrack_helper/src/api/gps_client.dart';
import 'package:unitrack_helper/src/models/gps_fix.dart';

/// Locks the wire format against the backend's `GpsBatch` / `GpsPointIn`
/// schemas. If these drift, tracking fails with a 422 five seconds into a trip
/// rather than at compile time.
void main() {
  final fix = GpsFix(
    lat: 23.7808,
    lng: 90.4064,
    ts: DateTime.utc(2026, 7, 16, 10, 30),
    speed: 8.5,
    heading: 90,
    accuracy: 4,
  );

  GpsClient clientReturning(http.Response response, {void Function(http.Request)? onRequest}) {
    return GpsClient(
      baseUrl: 'http://test.local',
      httpClient: MockClient((request) async {
        onRequest?.call(request);
        return response;
      }),
    );
  }

  test('posts a batch the backend schema accepts', () async {
    late http.Request captured;
    final client = clientReturning(
      http.Response(
        jsonEncode({'accepted': 1, 'bus_id': 'b1'}),
        202,
        headers: {'content-type': 'application/json'},
      ),
      onRequest: (request) => captured = request,
    );

    final accepted = await client.sendBatch(
      token: 'tok',
      busId: 'bus-uuid',
      fixes: [fix],
    );

    expect(accepted, 1);
    expect(captured.url.path, '/helper/gps');
    expect(captured.headers['Authorization'], 'Bearer tok');

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['bus_id'], 'bus-uuid');

    final point = (body['points'] as List).single as Map<String, dynamic>;
    expect(point['lat'], 23.7808);
    expect(point['lng'], 90.4064);
    expect(point['ts'], '2026-07-16T10:30:00.000Z');
    expect(point['speed'], 8.5);
  });

  test('timestamps are sent as UTC even when the device clock is not', () async {
    late http.Request captured;
    final client = clientReturning(
      http.Response(jsonEncode({'accepted': 1, 'bus_id': 'b1'}), 202),
      onRequest: (request) => captured = request,
    );

    final local = GpsFix(
      lat: 1,
      lng: 2,
      ts: DateTime.utc(2026, 7, 16, 4, 0).toLocal(),
    );
    await client.sendBatch(token: 't', busId: 'b', fixes: [local]);

    final point =
        ((jsonDecode(captured.body) as Map)['points'] as List).single as Map;
    expect(point['ts'], '2026-07-16T04:00:00.000Z');
  });

  test('401 surfaces as an auth failure, not a retryable error', () async {
    final client = clientReturning(
      http.Response(jsonEncode({'detail': 'Invalid or expired token'}), 401),
    );

    expect(
      () => client.sendBatch(token: 'stale', busId: 'b', fixes: [fix]),
      throwsA(
        isA<GpsAuthException>().having(
          (e) => e.message,
          'message',
          'Invalid or expired token',
        ),
      ),
    );
  });

  test('unapproved helper (403) is an auth failure', () async {
    final client = clientReturning(
      http.Response(jsonEncode({'detail': 'Helper account not approved'}), 403),
    );

    expect(
      () => client.sendBatch(token: 't', busId: 'b', fixes: [fix]),
      throwsA(isA<GpsAuthException>()),
    );
  });

  test('unknown bus (404) is retryable and keeps its detail', () async {
    final client = clientReturning(
      http.Response(jsonEncode({'detail': 'Unknown bus'}), 404),
    );

    expect(
      () => client.sendBatch(token: 't', busId: 'nope', fixes: [fix]),
      throwsA(
        isA<GpsRequestException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.message, 'message', 'Unknown bus'),
      ),
    );
  });

  test('a non-JSON error body does not crash the parser', () async {
    final client = clientReturning(http.Response('<html>502</html>', 502));

    expect(
      () => client.sendBatch(token: 't', busId: 'b', fixes: [fix]),
      throwsA(isA<GpsRequestException>().having((e) => e.statusCode, 'statusCode', 502)),
    );
  });
}
